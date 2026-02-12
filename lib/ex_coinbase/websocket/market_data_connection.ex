defmodule ExCoinbase.WebSocket.MarketDataConnection do
  @moduledoc """
  GenServer managing a Coinbase Advanced Trade public market data WebSocket connection.

  Handles:
  - Establishing and maintaining WebSocket connections to the public market data endpoint
  - Subscribing to level2, ticker, ticker_batch, and market_trades channels
  - Broadcasting parsed events to subscribers
  - Automatic reconnection with exponential backoff

  ## Usage

      {:ok, pid} = ExCoinbase.WebSocket.MarketDataConnection.start_link()

      ExCoinbase.WebSocket.MarketDataConnection.add_subscriber(pid, self())
      ExCoinbase.WebSocket.MarketDataConnection.subscribe(pid, "ticker", ["BTC-USD", "ETH-USD"])

      # You'll receive messages like:
      # {:coinbase_market_event, :ticker, %ExCoinbase.WebSocket.TickerEvent{...}}
  """

  use GenServer

  require Logger

  alias ExCoinbase.WebSocket
  alias ExCoinbase.WebSocket.Client, as: StreamClient

  @reconnect_base_delay_ms 1_000
  @reconnect_max_delay_ms 30_000
  @max_reconnect_attempts 10

  defmodule State do
    @moduledoc false
    defstruct [
      :websocket_pid,
      :subscribers,
      :status,
      :reconnect_attempts,
      :reconnect_timer,
      :subscribe_timer,
      :channel_subscriptions
    ]

    @type status :: :disconnected | :connecting | :connected | :reconnecting

    @type t :: %__MODULE__{
            websocket_pid: pid() | nil,
            subscribers: MapSet.t(),
            status: status(),
            reconnect_attempts: non_neg_integer(),
            reconnect_timer: reference() | nil,
            subscribe_timer: reference() | nil,
            channel_subscriptions: %{String.t() => MapSet.t()}
          }
  end

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Starts a MarketDataConnection process.

  ## Options

    - `:name` - Optional. Process name for registration
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, :ok, gen_opts)
  end

  @doc """
  Subscribes to a market data channel for the given products.

  Valid channels: "level2", "ticker", "ticker_batch", "market_trades"

  ## Examples

      MarketDataConnection.subscribe(pid, "ticker", ["BTC-USD", "ETH-USD"])
  """
  def subscribe(server, channel, products) when is_binary(channel) and is_list(products) do
    GenServer.call(server, {:subscribe, channel, products})
  end

  @doc """
  Unsubscribes from a market data channel for the given products.
  """
  def unsubscribe(server, channel, products) when is_binary(channel) and is_list(products) do
    GenServer.call(server, {:unsubscribe, channel, products})
  end

  @doc """
  Registers a process to receive market data events.

  Events are sent as `{:coinbase_market_event, channel_atom, event}` messages.
  """
  def add_subscriber(server, subscriber_pid) when is_pid(subscriber_pid) do
    GenServer.cast(server, {:add_subscriber, subscriber_pid})
  end

  @doc "Unregisters a process from receiving events."
  def remove_subscriber(server, subscriber_pid) when is_pid(subscriber_pid) do
    GenServer.cast(server, {:remove_subscriber, subscriber_pid})
  end

  @doc "Gets the current connection status."
  def get_status(server), do: GenServer.call(server, :get_status)

  @doc "Gets connection info including status, channels, and subscriber count."
  def get_info(server), do: GenServer.call(server, :get_info)

  @doc "Forces a reconnection."
  def reconnect(server), do: GenServer.cast(server, :reconnect)

  @doc "Stops the connection gracefully."
  def stop(server), do: GenServer.stop(server, :normal)

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl GenServer
  def init(:ok) do
    state = %State{
      websocket_pid: nil,
      subscribers: MapSet.new(),
      status: :disconnected,
      reconnect_attempts: 0,
      reconnect_timer: nil,
      subscribe_timer: nil,
      channel_subscriptions: %{}
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:subscribe, channel, products}, _from, state) do
    new_products = MapSet.new(products)
    current = Map.get(state.channel_subscriptions, channel, MapSet.new())
    updated = MapSet.union(current, new_products)
    channel_subs = Map.put(state.channel_subscriptions, channel, updated)
    state = %{state | channel_subscriptions: channel_subs}

    if state.status == :connected and state.websocket_pid do
      send_channel_subscription(state, channel)
    end

    {:reply, :ok, maybe_connect(state)}
  end

  @impl GenServer
  def handle_call({:unsubscribe, channel, products}, _from, state) do
    remove_products = MapSet.new(products)
    current = Map.get(state.channel_subscriptions, channel, MapSet.new())
    updated = MapSet.difference(current, remove_products)

    channel_subs =
      if MapSet.size(updated) == 0 do
        Map.delete(state.channel_subscriptions, channel)
      else
        Map.put(state.channel_subscriptions, channel, updated)
      end

    state = %{state | channel_subscriptions: channel_subs}

    if state.status == :connected and state.websocket_pid do
      send_channel_unsubscribe(state, channel, products)
    end

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call(:get_status, _from, state) do
    {:reply, state.status, state}
  end

  @impl GenServer
  def handle_call(:get_info, _from, state) do
    channels =
      state.channel_subscriptions
      |> Enum.map(fn {channel, products} -> {channel, MapSet.to_list(products)} end)
      |> Map.new()

    info = %{
      status: state.status,
      channels: channels,
      subscriber_count: MapSet.size(state.subscribers)
    }

    {:reply, info, state}
  end

  @impl GenServer
  def handle_cast({:add_subscriber, pid}, state) do
    Logger.info("[MarketDataConnection] Adding subscriber: #{inspect(pid)}")
    Process.monitor(pid)
    {:noreply, %{state | subscribers: MapSet.put(state.subscribers, pid)}}
  end

  @impl GenServer
  def handle_cast({:remove_subscriber, pid}, state) do
    {:noreply, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end

  @impl GenServer
  def handle_cast(:reconnect, state) do
    state = disconnect(state)
    {:noreply, schedule_reconnect(state)}
  end

  @impl GenServer
  def handle_info({:stream_connected, ws_pid}, %{websocket_pid: ws_pid} = state) do
    Logger.info("[MarketDataConnection] WebSocket connected")

    state = %{state | status: :connected, reconnect_attempts: 0}
    state = schedule_subscribe(state)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:send_subscriptions, state) do
    state = %{state | subscribe_timer: nil}

    if state.status == :connected and state.websocket_pid do
      send_all_subscriptions(state)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:stream_message, ws_pid, message}, %{websocket_pid: ws_pid} = state) do
    case WebSocket.parse_event(message) do
      {:ok, channel, event}
      when channel in [:level2, :ticker, :ticker_batch, :market_trades] ->
        Logger.debug(
          "[MarketDataConnection] #{channel} event - broadcasting to #{MapSet.size(state.subscribers)} subscriber(s)"
        )

        broadcast_market_event(state.subscribers, channel, event)

      {:ok, :heartbeat, _event} ->
        Logger.debug("[MarketDataConnection] Heartbeat received")

      {:ok, :subscriptions, data} ->
        Logger.info("[MarketDataConnection] Subscription confirmed: #{inspect(data)}")

      {:error, {:server_error, error_message}} ->
        Logger.error("[MarketDataConnection] Server error: #{error_message}")

      {:error, reason} ->
        Logger.debug("[MarketDataConnection] Failed to parse message: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:stream_disconnected, ws_pid, reason}, %{websocket_pid: ws_pid} = state) do
    Logger.warning("[MarketDataConnection] WebSocket disconnected: #{inspect(reason)}")
    state = %{state | websocket_pid: nil, status: :disconnected}
    state = cancel_timer(state, :subscribe_timer)
    {:noreply, schedule_reconnect(state)}
  end

  @impl GenServer
  def handle_info(:reconnect, state) do
    Logger.info(
      "[MarketDataConnection] Attempting to reconnect (attempt #{state.reconnect_attempts + 1})"
    )

    {:noreply, do_connect(%{state | reconnect_timer: nil})}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end

  @impl GenServer
  def handle_info(msg, state) do
    Logger.debug("[MarketDataConnection] Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    cancel_timer(state, :reconnect_timer)
    cancel_timer(state, :subscribe_timer)

    if state.websocket_pid do
      maybe_unsubscribe_before_close(state)
      StreamClient.close(state.websocket_pid)
    end

    :ok
  end

  defp maybe_unsubscribe_before_close(%{status: :connected} = state) do
    state.channel_subscriptions
    |> Enum.map(fn {channel, products} -> {channel, MapSet.to_list(products)} end)
    |> Enum.reject(fn {_channel, products} -> products == [] end)
    |> Enum.each(fn {channel, products} ->
      unsubscribe_msg = WebSocket.build_unsubscribe_message(channel, products)
      StreamClient.send_message(state.websocket_pid, unsubscribe_msg)
    end)

    Process.sleep(100)
  end

  defp maybe_unsubscribe_before_close(_state), do: :ok

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp maybe_connect(%{status: :connected} = state), do: state
  defp maybe_connect(%{status: :connecting} = state), do: state

  defp maybe_connect(%{channel_subscriptions: subs} = state) when map_size(subs) == 0,
    do: state

  defp maybe_connect(state), do: do_connect(state)

  defp do_connect(state) do
    state = %{state | status: :connecting}
    url = WebSocket.websocket_url()

    case StreamClient.start_link(url, self()) do
      {:ok, ws_pid} ->
        %{state | websocket_pid: ws_pid}

      {:error, reason} ->
        Logger.error("[MarketDataConnection] Failed to connect WebSocket: #{inspect(reason)}")
        schedule_reconnect(%{state | status: :disconnected})
    end
  end

  defp schedule_subscribe(state) do
    timer = Process.send_after(self(), :send_subscriptions, 0)
    %{state | subscribe_timer: timer}
  end

  defp send_all_subscriptions(state) do
    Enum.each(state.channel_subscriptions, fn {channel, _products} ->
      send_channel_subscription(state, channel)
    end)
  end

  defp send_channel_subscription(state, channel) do
    products = Map.get(state.channel_subscriptions, channel, MapSet.new()) |> MapSet.to_list()

    if products != [] and state.websocket_pid do
      Logger.info(
        "[MarketDataConnection] Subscribing to #{channel} for products: #{inspect(products)}"
      )

      subscribe_msg = WebSocket.build_subscribe_message(channel, products, nil)
      StreamClient.send_message(state.websocket_pid, subscribe_msg)
    end
  end

  defp send_channel_unsubscribe(state, channel, products) do
    if state.websocket_pid && products != [] do
      unsubscribe_msg = WebSocket.build_unsubscribe_message(channel, products)
      StreamClient.send_message(state.websocket_pid, unsubscribe_msg)
    end
  end

  defp broadcast_market_event(subscribers, channel, event) do
    Enum.each(subscribers, fn pid ->
      send(pid, {:coinbase_market_event, channel, event})
    end)
  end

  defp schedule_reconnect(state) when state.reconnect_attempts >= @max_reconnect_attempts do
    Logger.error("[MarketDataConnection] Max reconnect attempts reached")
    %{state | status: :disconnected}
  end

  defp schedule_reconnect(state) do
    state = cancel_timer(state, :reconnect_timer)

    delay = calculate_backoff_delay(state.reconnect_attempts)
    timer = Process.send_after(self(), :reconnect, delay)

    Logger.info("[MarketDataConnection] Scheduling reconnect in #{delay}ms")

    %{
      state
      | reconnect_timer: timer,
        reconnect_attempts: state.reconnect_attempts + 1,
        status: :reconnecting
    }
  end

  defp calculate_backoff_delay(attempts) do
    delay = @reconnect_base_delay_ms * :math.pow(2, attempts)
    min(round(delay), @reconnect_max_delay_ms)
  end

  defp disconnect(state) do
    state = cancel_timer(state, :reconnect_timer)
    state = cancel_timer(state, :subscribe_timer)

    if state.websocket_pid do
      StreamClient.close(state.websocket_pid)
    end

    %{
      state
      | websocket_pid: nil,
        status: :disconnected,
        reconnect_timer: nil,
        subscribe_timer: nil
    }
  end

  defp cancel_timer(state, field) do
    case Map.get(state, field) do
      nil ->
        state

      ref ->
        Process.cancel_timer(ref)
        Map.put(state, field, nil)
    end
  end
end
