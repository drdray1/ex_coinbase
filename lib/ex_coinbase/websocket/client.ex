defmodule ExCoinbase.WebSocket.Client do
  @moduledoc """
  WebSockex client for Coinbase Advanced Trade WebSocket connections.

  Wraps WebSockex to handle the actual WebSocket connection, forwarding
  all received messages to a parent process.

  ## Usage

      {:ok, pid} = ExCoinbase.WebSocket.Client.start_link(url, self())
      ExCoinbase.WebSocket.Client.send_message(pid, %{"type" => "subscribe", ...})

  Messages received from the WebSocket will be sent to the parent process as:
  - `{:stream_connected, pid}` - When connection is established
  - `{:stream_message, pid, message}` - For each received message
  - `{:stream_disconnected, pid, reason}` - When disconnected
  """

  use WebSockex

  require Logger

  defmodule State do
    @moduledoc false
    defstruct [:parent_pid, :connected]
  end

  @doc """
  Starts a WebSocket connection to the given URL.

  ## Parameters

    - `url` - The WebSocket URL to connect to
    - `parent_pid` - The process to send messages to
    - `opts` - Optional WebSockex options
  """
  def start_link(url, parent_pid, opts \\ []) do
    state = %State{parent_pid: parent_pid, connected: false}

    websockex_opts =
      opts
      |> Keyword.delete(:name)
      |> Keyword.put_new(:handle_initial_conn_failure, true)

    WebSockex.start_link(url, __MODULE__, state, websockex_opts)
  end

  @doc """
  Sends a message payload to the WebSocket.

  The message map will be JSON encoded before sending.
  """
  def send_message(pid, message) when is_map(message) do
    case Jason.encode(message) do
      {:ok, json} -> WebSockex.send_frame(pid, {:text, json})
      {:error, reason} -> {:error, {:encode_error, reason}}
    end
  end

  @doc """
  Sends a raw text frame to the WebSocket.
  """
  def send_text(pid, text) when is_binary(text) do
    WebSockex.send_frame(pid, {:text, text})
  end

  @doc """
  Closes the WebSocket connection gracefully.
  """
  def close(pid) do
    WebSockex.cast(pid, :close)
  end

  # ============================================================================
  # WebSockex Callbacks
  # ============================================================================

  @impl WebSockex
  def handle_connect(_conn, state) do
    Logger.debug("[ExCoinbase.WebSocket.Client] Connected to WebSocket")
    send(state.parent_pid, {:stream_connected, self()})
    {:ok, %{state | connected: true}}
  end

  @impl WebSockex
  def handle_frame({:text, msg}, state) do
    Logger.debug("[ExCoinbase.WebSocket.Client] Received: #{String.slice(msg, 0, 200)}...")
    send(state.parent_pid, {:stream_message, self(), msg})
    {:ok, state}
  end

  @impl WebSockex
  def handle_frame({:binary, msg}, state) do
    Logger.debug("[ExCoinbase.WebSocket.Client] Received binary frame: #{byte_size(msg)} bytes")
    send(state.parent_pid, {:stream_binary, self(), msg})
    {:ok, state}
  end

  @impl WebSockex
  def handle_frame({:ping, msg}, state) do
    Logger.debug("[ExCoinbase.WebSocket.Client] Received ping")
    {:reply, {:pong, msg}, state}
  end

  @impl WebSockex
  def handle_frame({:pong, _msg}, state) do
    Logger.debug("[ExCoinbase.WebSocket.Client] Received pong")
    {:ok, state}
  end

  @impl WebSockex
  def handle_disconnect(disconnect_map, state) do
    reason = disconnect_map[:reason] || :unknown
    Logger.warning("[ExCoinbase.WebSocket.Client] Disconnected: #{inspect(reason)}")
    send(state.parent_pid, {:stream_disconnected, self(), reason})
    {:ok, %{state | connected: false}}
  end

  @impl WebSockex
  def handle_cast(:close, state) do
    Logger.debug("[ExCoinbase.WebSocket.Client] Closing connection")
    {:close, state}
  end

  @impl WebSockex
  def handle_cast({:send, frame}, state) do
    {:reply, frame, state}
  end

  @impl WebSockex
  def handle_info(msg, state) do
    Logger.debug("[ExCoinbase.WebSocket.Client] Received info: #{inspect(msg)}")
    {:ok, state}
  end

  @impl WebSockex
  def terminate(reason, state) do
    Logger.debug("[ExCoinbase.WebSocket.Client] Terminating: #{inspect(reason)}")

    if state.connected do
      send(state.parent_pid, {:stream_disconnected, self(), reason})
    end

    :ok
  end
end
