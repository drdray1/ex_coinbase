defmodule ExCoinbase.WebSocket.Connection do
  @moduledoc """
  GenServer managing a Coinbase Advanced Trade user WebSocket connection.

  Handles:
  - Establishing and maintaining WebSocket connections to the user endpoint
  - JWT-authenticated subscriptions for order updates
  - Automatic JWT refresh before expiry (120s TTL)
  - Managing product subscriptions for the user channel
  - Broadcasting parsed events to subscribers
  - Automatic reconnection with exponential backoff

  ## Usage

      {:ok, pid} = ExCoinbase.WebSocket.Connection.start_link(
        api_key_id: "organizations/org/apiKeys/key",
        private_key_pem: "-----BEGIN EC PRIVATE KEY-----..."
      )

      ExCoinbase.WebSocket.Connection.add_subscriber(pid, self())
      ExCoinbase.WebSocket.Connection.subscribe(pid, ["BTC-USD", "ETH-USD"])

      # You'll receive messages like:
      # {:coinbase_user_event, %ExCoinbase.WebSocket.UserOrderEvent{...}}
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
      :api_key_id,
      :private_key_pem,
      :websocket_pid,
      :subscribed_products,
      :subscribers,
      :status,
      :reconnect_attempts,
      :reconnect_timer,
      :jwt_refresh_timer,
      :subscribe_timer
    ]

    @type status :: :disconnected | :connecting | :connected | :reconnecting

    @type t :: %__MODULE__{
            api_key_id: String.t(),
            private_key_pem: String.t(),
            websocket_pid: pid() | nil,
            subscribed_products: MapSet.t(),
            subscribers: MapSet.t(),
            status: status(),
            reconnect_attempts: non_neg_integer(),
            reconnect_timer: reference() | nil,
            jwt_refresh_timer: reference() | nil,
            subscribe_timer: reference() | nil
          }
  end

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Starts a Connection process.

  ## Options

    - `:api_key_id` - Required. The Coinbase API key ID
    - `:private_key_pem` - Required. The EC private key in PEM format
    - `:name` - Optional. Process name for registration
  """
  def start_link(opts) do
    api_key_id = Keyword.fetch!(opts, :api_key_id)
    private_key_pem = Keyword.fetch!(opts, :private_key_pem)
    name = Keyword.get(opts, :name)

    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, {api_key_id, private_key_pem}, gen_opts)
  end

  @doc """
  Subscribes to products for streaming order updates.

  ## Examples

      ExCoinbase.WebSocket.Connection.subscribe(pid, ["BTC-USD", "ETH-USD"])
  """
  def subscribe(server, products) when is_list(products) do
    GenServer.call(server, {:subscribe, products})
  end

  @doc """
  Unsubscribes from products.
  """
  def unsubscribe(server, products) when is_list(products) do
    GenServer.call(server, {:unsubscribe, products})
  end

  @doc """
  Registers a process to receive streaming events.

  Events are sent as `{:coinbase_user_event, event}` messages.
  """
  def add_subscriber(server, subscriber_pid) when is_pid(subscriber_pid) do
    GenServer.cast(server, {:add_subscriber, subscriber_pid})
  end

  @doc """
  Unregisters a process from receiving events.
  """
  def remove_subscriber(server, subscriber_pid) when is_pid(subscriber_pid) do
    GenServer.cast(server, {:remove_subscriber, subscriber_pid})
  end

  @doc """
  Gets the current connection status.

  Returns `:disconnected`, `:connecting`, `:connected`, or `:reconnecting`.
  """
  def get_status(server) do
    GenServer.call(server, :get_status)
  end

  @doc """
  Gets information about the current connection.

  Returns a map with `:status`, `:products`, and `:subscriber_count`.
  """
  def get_info(server) do
    GenServer.call(server, :get_info)
  end

  @doc "Forces a reconnection to the WebSocket."
  def reconnect(server) do
    GenServer.cast(server, :reconnect)
  end

  @doc "Stops the connection gracefully."
  def stop(server) do
    GenServer.stop(server, :normal)
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl GenServer
  def init({api_key_id, private_key_pem}) do
    state = %State{
      api_key_id: api_key_id,
      private_key_pem: private_key_pem,
      websocket_pid: nil,
      subscribed_products: MapSet.new(),
      subscribers: MapSet.new(),
      status: :disconnected,
      reconnect_attempts: 0,
      reconnect_timer: nil,
      jwt_refresh_timer: nil,
      subscribe_timer: nil
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:subscribe, products}, _from, state) do
    new_products = MapSet.new(products)
    updated_products = MapSet.union(state.subscribed_products, new_products)
    state = %{state | subscribed_products: updated_products}

    if state.status == :connected and state.websocket_pid do
      send_user_subscription(state)
    end

    {:reply, :ok, maybe_connect(state)}
  end

  @impl GenServer
  def handle_call({:unsubscribe, products}, _from, state) do
    remove_products = MapSet.new(products)
    updated_products = MapSet.difference(state.subscribed_products, remove_products)
    state = %{state | subscribed_products: updated_products}

    if state.status == :connected and state.websocket_pid do
      send_unsubscribe(state, products)
    end

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call(:get_status, _from, state) do
    {:reply, state.status, state}
  end

  @impl GenServer
  def handle_call(:get_info, _from, state) do
    info = %{
      status: state.status,
      products: MapSet.to_list(state.subscribed_products),
      subscriber_count: MapSet.size(state.subscribers)
    }

    {:reply, info, state}
  end

  @impl GenServer
  def handle_cast({:add_subscriber, pid}, state) do
    Logger.info("[ExCoinbase.WebSocket.Connection] Adding subscriber: #{inspect(pid)}")
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
    Logger.info("[ExCoinbase.WebSocket.Connection] WebSocket connected")

    state = %{state | status: :connected, reconnect_attempts: 0}
    state = schedule_subscribe(state)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:send_subscriptions, state) do
    state = %{state | subscribe_timer: nil}

    if state.status == :connected and state.websocket_pid do
      send_heartbeat_subscription(state)
      send_user_subscription(state)
      state = schedule_jwt_refresh(state)

      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:stream_message, ws_pid, message}, %{websocket_pid: ws_pid} = state) do
    case WebSocket.parse_event(message) do
      {:ok, :user, event} ->
        Logger.info(
          "[ExCoinbase.WebSocket.Connection] User event received - broadcasting to #{MapSet.size(state.subscribers)} subscriber(s)"
        )

        broadcast_event(state.subscribers, event)

      {:ok, :heartbeat, _event} ->
        Logger.debug("[ExCoinbase.WebSocket.Connection] Heartbeat received")

      {:ok, :subscriptions, data} ->
        Logger.info("[ExCoinbase.WebSocket.Connection] Subscription confirmed: #{inspect(data)}")

      {:error, {:server_error, error_message}} ->
        Logger.error("[ExCoinbase.WebSocket.Connection] Server error: #{error_message}")

      {:error, reason} ->
        Logger.debug(
          "[ExCoinbase.WebSocket.Connection] Failed to parse message: #{inspect(reason)}"
        )
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:stream_disconnected, ws_pid, reason}, %{websocket_pid: ws_pid} = state) do
    Logger.warning("[ExCoinbase.WebSocket.Connection] WebSocket disconnected: #{inspect(reason)}")
    state = %{state | websocket_pid: nil, status: :disconnected}
    state = cancel_timer(state, :jwt_refresh_timer)
    state = cancel_timer(state, :subscribe_timer)
    {:noreply, schedule_reconnect(state)}
  end

  @impl GenServer
  def handle_info(:reconnect, state) do
    Logger.info(
      "[ExCoinbase.WebSocket.Connection] Attempting to reconnect (attempt #{state.reconnect_attempts + 1})"
    )

    {:noreply, do_connect(%{state | reconnect_timer: nil})}
  end

  @impl GenServer
  def handle_info(:refresh_jwt, state) do
    Logger.info("[ExCoinbase.WebSocket.Connection] Refreshing JWT")
    state = %{state | jwt_refresh_timer: nil}

    if state.status == :connected and state.websocket_pid do
      send_user_subscription(state)
      state = schedule_jwt_refresh(state)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end

  @impl GenServer
  def handle_info(msg, state) do
    Logger.debug("[ExCoinbase.WebSocket.Connection] Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    cancel_timer(state, :reconnect_timer)
    cancel_timer(state, :jwt_refresh_timer)
    cancel_timer(state, :subscribe_timer)

    if state.websocket_pid do
      maybe_unsubscribe_before_close(state)
      StreamClient.close(state.websocket_pid)
    end

    :ok
  end

  defp maybe_unsubscribe_before_close(state) do
    if state.status == :connected do
      products = MapSet.to_list(state.subscribed_products)

      if products != [] do
        unsubscribe_msg = WebSocket.build_unsubscribe_message("user", products)
        StreamClient.send_message(state.websocket_pid, unsubscribe_msg)
        Process.sleep(100)
      end
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp maybe_connect(%{status: :connected} = state), do: state
  defp maybe_connect(%{status: :connecting} = state), do: state

  defp maybe_connect(%{subscribed_products: products} = state) when map_size(products) == 0,
    do: state

  defp maybe_connect(state), do: do_connect(state)

  defp do_connect(state) do
    state = %{state | status: :connecting}
    url = WebSocket.websocket_user_url()

    case StreamClient.start_link(url, self()) do
      {:ok, ws_pid} ->
        %{state | websocket_pid: ws_pid}

      {:error, reason} ->
        Logger.error(
          "[ExCoinbase.WebSocket.Connection] Failed to connect WebSocket: #{inspect(reason)}"
        )

        schedule_reconnect(%{state | status: :disconnected})
    end
  end

  defp schedule_subscribe(state) do
    timer = Process.send_after(self(), :send_subscriptions, 0)
    %{state | subscribe_timer: timer}
  end

  defp send_heartbeat_subscription(state) do
    if state.websocket_pid do
      heartbeat_msg = WebSocket.build_subscribe_message("heartbeats", [], nil)
      StreamClient.send_message(state.websocket_pid, heartbeat_msg)
    end
  end

  defp send_user_subscription(state) do
    products = MapSet.to_list(state.subscribed_products)

    if products != [] and state.websocket_pid do
      Logger.info(
        "[ExCoinbase.WebSocket.Connection] Sending user channel subscription for products: #{inspect(products)}"
      )

      case WebSocket.build_authenticated_subscribe(
             state.api_key_id,
             state.private_key_pem,
             products
           ) do
        {:ok, subscribe_msg} ->
          StreamClient.send_message(state.websocket_pid, subscribe_msg)

        {:error, reason} ->
          Logger.error(
            "[ExCoinbase.WebSocket.Connection] Failed to generate JWT: #{inspect(reason)}"
          )
      end
    end
  end

  defp send_unsubscribe(state, products) do
    if state.websocket_pid && products != [] do
      unsubscribe_msg = WebSocket.build_unsubscribe_message("user", products)
      StreamClient.send_message(state.websocket_pid, unsubscribe_msg)
    end
  end

  defp broadcast_event(subscribers, event) do
    Enum.each(subscribers, fn pid ->
      send(pid, {:coinbase_user_event, event})
    end)
  end

  defp schedule_reconnect(state) when state.reconnect_attempts >= @max_reconnect_attempts do
    Logger.error("[ExCoinbase.WebSocket.Connection] Max reconnect attempts reached")
    %{state | status: :disconnected}
  end

  defp schedule_reconnect(state) do
    state = cancel_timer(state, :reconnect_timer)

    delay = calculate_backoff_delay(state.reconnect_attempts)
    timer = Process.send_after(self(), :reconnect, delay)

    Logger.info("[ExCoinbase.WebSocket.Connection] Scheduling reconnect in #{delay}ms")

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

  defp schedule_jwt_refresh(state) do
    state = cancel_timer(state, :jwt_refresh_timer)

    refresh_in = WebSocket.jwt_refresh_interval_ms()
    timer = Process.send_after(self(), :refresh_jwt, refresh_in)

    Logger.debug("[ExCoinbase.WebSocket.Connection] Scheduling JWT refresh in #{refresh_in}ms")
    %{state | jwt_refresh_timer: timer}
  end

  defp disconnect(state) do
    state = cancel_timer(state, :reconnect_timer)
    state = cancel_timer(state, :jwt_refresh_timer)
    state = cancel_timer(state, :subscribe_timer)

    if state.websocket_pid do
      StreamClient.close(state.websocket_pid)
    end

    %{
      state
      | websocket_pid: nil,
        status: :disconnected,
        reconnect_timer: nil,
        jwt_refresh_timer: nil,
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
