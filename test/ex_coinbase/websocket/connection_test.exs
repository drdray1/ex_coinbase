defmodule ExCoinbase.WebSocket.ConnectionTest do
  use ExUnit.Case, async: false
  use Mimic

  alias ExCoinbase.WebSocket.Connection

  @test_api_key "organizations/test-org/apiKeys/test-key"
  @test_pem """
  -----BEGIN EC PRIVATE KEY-----
  MHcCAQEEIJu/Ze6KwFX6kqjf0YTCwuFtFwcaIA6NfRc2XaioC8DdoAoGCCqGSM49
  AwEHoUQDQgAE6ob5+ow9MXBF4R28xeIzj5djEWB9OM681bQ2IlqjV4LJAKdRyPRX
  7cjqMZo/TspePuKrd936h3l17oeU4qlgHw==
  -----END EC PRIVATE KEY-----
  """

  setup :verify_on_exit!

  setup do
    # start_link is called with 2 args from do_connect (opts has default)
    stub(ExCoinbase.WebSocket.Client, :start_link, fn _url, _parent ->
      {:ok, spawn(fn -> Process.sleep(:infinity) end)}
    end)

    stub(ExCoinbase.WebSocket.Client, :send_message, fn _pid, _msg -> :ok end)
    stub(ExCoinbase.WebSocket.Client, :close, fn _pid -> :ok end)

    stub(ExCoinbase.WebSocket, :websocket_user_url, fn ->
      "wss://test.example.com"
    end)

    stub(ExCoinbase.WebSocket, :build_authenticated_subscribe, fn _key, _pem, _products ->
      {:ok, %{"type" => "subscribe", "channel" => "user", "product_ids" => ["BTC-USD"]}}
    end)

    stub(ExCoinbase.WebSocket, :build_subscribe_message, fn channel, _products, _jwt ->
      %{"type" => "subscribe", "channel" => channel}
    end)

    stub(ExCoinbase.WebSocket, :build_unsubscribe_message, fn channel, products ->
      %{"type" => "unsubscribe", "channel" => channel, "product_ids" => products}
    end)

    stub(ExCoinbase.WebSocket, :jwt_refresh_interval_ms, fn -> 100_000 end)

    stub(ExCoinbase.WebSocket, :parse_event, fn _msg ->
      {:ok, :heartbeat, %ExCoinbase.WebSocket.HeartbeatEvent{channel: "heartbeats"}}
    end)

    :ok
  end

  defp start_connection(opts \\ []) do
    default_opts = [api_key_id: @test_api_key, private_key_pem: @test_pem]
    {:ok, pid} = Connection.start_link(Keyword.merge(default_opts, opts))

    on_exit(fn ->
      if Process.alive?(pid), do: Connection.stop(pid)
    end)

    pid
  end

  # ============================================================================
  # Lifecycle Tests
  # ============================================================================

  describe "start_link/1" do
    test "starts GenServer with required options" do
      pid = start_connection()
      assert Process.alive?(pid)
    end

    test "raises when api_key_id is missing" do
      assert_raise KeyError, fn ->
        Connection.start_link(private_key_pem: @test_pem)
      end
    end

    test "raises when private_key_pem is missing" do
      assert_raise KeyError, fn ->
        Connection.start_link(api_key_id: @test_api_key)
      end
    end
  end

  # ============================================================================
  # Status Tests
  # ============================================================================

  describe "get_status/1" do
    test "returns :disconnected initially" do
      pid = start_connection()
      assert Connection.get_status(pid) == :disconnected
    end
  end

  describe "get_info/1" do
    test "returns status, products, and subscriber_count" do
      pid = start_connection()
      info = Connection.get_info(pid)

      assert info.status == :disconnected
      assert info.products == []
      assert info.subscriber_count == 0
    end
  end

  # ============================================================================
  # Subscription Tests
  # ============================================================================

  describe "subscribe/2" do
    test "triggers connection when products are added" do
      pid = start_connection()
      assert :ok = Connection.subscribe(pid, ["BTC-USD"])

      Process.sleep(50)
      status = Connection.get_status(pid)
      assert status in [:connecting, :connected]
    end

    test "adds products to subscribed set" do
      pid = start_connection()
      Connection.subscribe(pid, ["BTC-USD"])
      Connection.subscribe(pid, ["ETH-USD"])

      Process.sleep(50)
      info = Connection.get_info(pid)
      assert "BTC-USD" in info.products
      assert "ETH-USD" in info.products
    end
  end

  describe "unsubscribe/2" do
    test "removes products from subscribed set" do
      pid = start_connection()
      Connection.subscribe(pid, ["BTC-USD", "ETH-USD"])
      Process.sleep(50)

      Connection.unsubscribe(pid, ["ETH-USD"])
      info = Connection.get_info(pid)

      assert "BTC-USD" in info.products
      refute "ETH-USD" in info.products
    end
  end

  # ============================================================================
  # Subscriber Management Tests
  # ============================================================================

  describe "add_subscriber/2 and remove_subscriber/2" do
    test "adds and removes subscriber" do
      pid = start_connection()

      Connection.add_subscriber(pid, self())
      Process.sleep(50)
      assert Connection.get_info(pid).subscriber_count == 1

      Connection.remove_subscriber(pid, self())
      Process.sleep(50)
      assert Connection.get_info(pid).subscriber_count == 0
    end

    test "auto-removes subscriber on process exit" do
      pid = start_connection()

      subscriber = spawn(fn -> Process.sleep(:infinity) end)
      Connection.add_subscriber(pid, subscriber)
      Process.sleep(50)
      assert Connection.get_info(pid).subscriber_count == 1

      Process.exit(subscriber, :kill)
      Process.sleep(50)
      assert Connection.get_info(pid).subscriber_count == 0
    end
  end

  # ============================================================================
  # Event Broadcasting Tests
  # ============================================================================

  describe "stream event handling" do
    test "broadcasts user events to subscribers" do
      user_event = %ExCoinbase.WebSocket.UserOrderEvent{
        channel: "user",
        events: []
      }

      stub(ExCoinbase.WebSocket, :parse_event, fn _msg ->
        {:ok, :user, user_event}
      end)

      pid = start_connection()
      Connection.add_subscriber(pid, self())
      Connection.subscribe(pid, ["BTC-USD"])
      Process.sleep(50)

      # Get the websocket PID from internal state
      state = :sys.get_state(pid)

      # Simulate connection established and a message received
      send(pid, {:stream_connected, state.websocket_pid})
      Process.sleep(50)
      send(pid, {:stream_message, state.websocket_pid, ~s({"channel":"user","events":[]})})

      assert_receive {:coinbase_user_event, ^user_event}, 500
    end

    test "handles heartbeat messages without broadcasting" do
      stub(ExCoinbase.WebSocket, :parse_event, fn _msg ->
        {:ok, :heartbeat, %ExCoinbase.WebSocket.HeartbeatEvent{channel: "heartbeats"}}
      end)

      pid = start_connection()
      Connection.add_subscriber(pid, self())
      Connection.subscribe(pid, ["BTC-USD"])
      Process.sleep(50)

      state = :sys.get_state(pid)
      send(pid, {:stream_connected, state.websocket_pid})
      Process.sleep(50)
      send(pid, {:stream_message, state.websocket_pid, ~s({"channel":"heartbeats"})})
      Process.sleep(50)

      refute_receive {:coinbase_user_event, _}
    end

    test "handles subscriptions messages without crashing" do
      stub(ExCoinbase.WebSocket, :parse_event, fn _msg ->
        {:ok, :subscriptions, %{"subscriptions" => %{}}}
      end)

      pid = start_connection()
      Connection.subscribe(pid, ["BTC-USD"])
      Process.sleep(50)

      state = :sys.get_state(pid)
      send(pid, {:stream_connected, state.websocket_pid})
      Process.sleep(50)
      send(pid, {:stream_message, state.websocket_pid, ~s({"type":"subscriptions"})})
      Process.sleep(50)

      assert Process.alive?(pid)
    end

    test "handles server error messages without crashing" do
      stub(ExCoinbase.WebSocket, :parse_event, fn _msg ->
        {:error, {:server_error, "Something went wrong"}}
      end)

      pid = start_connection()
      Connection.subscribe(pid, ["BTC-USD"])
      Process.sleep(50)

      state = :sys.get_state(pid)
      send(pid, {:stream_connected, state.websocket_pid})
      Process.sleep(50)
      send(pid, {:stream_message, state.websocket_pid, ~s({"type":"error"})})
      Process.sleep(50)

      assert Process.alive?(pid)
    end

    test "handles parse errors without crashing" do
      stub(ExCoinbase.WebSocket, :parse_event, fn _msg ->
        {:error, :invalid_json}
      end)

      pid = start_connection()
      Connection.subscribe(pid, ["BTC-USD"])
      Process.sleep(50)

      state = :sys.get_state(pid)
      send(pid, {:stream_connected, state.websocket_pid})
      Process.sleep(50)
      send(pid, {:stream_message, state.websocket_pid, "bad data"})
      Process.sleep(50)

      assert Process.alive?(pid)
    end
  end

  # ============================================================================
  # Connected-state Subscription Tests
  # ============================================================================

  describe "subscribe when already connected" do
    test "sends subscription immediately when connected" do
      pid = start_connection()
      Connection.subscribe(pid, ["BTC-USD"])
      Process.sleep(50)

      state = :sys.get_state(pid)
      send(pid, {:stream_connected, state.websocket_pid})
      Process.sleep(100)

      # Now subscribe to additional products while connected
      Connection.subscribe(pid, ["ETH-USD"])
      Process.sleep(50)

      info = Connection.get_info(pid)
      assert "ETH-USD" in info.products
      assert "BTC-USD" in info.products
    end
  end

  describe "unsubscribe when connected" do
    test "sends unsubscribe message when connected" do
      pid = start_connection()
      Connection.subscribe(pid, ["BTC-USD", "ETH-USD"])
      Process.sleep(50)

      state = :sys.get_state(pid)
      send(pid, {:stream_connected, state.websocket_pid})
      Process.sleep(100)

      Connection.unsubscribe(pid, ["ETH-USD"])
      Process.sleep(50)

      info = Connection.get_info(pid)
      assert "BTC-USD" in info.products
      refute "ETH-USD" in info.products
    end
  end

  # ============================================================================
  # Send Subscriptions Handler Tests
  # ============================================================================

  describe ":send_subscriptions handler" do
    test "sends heartbeat and user subscriptions when connected" do
      pid = start_connection()
      Connection.subscribe(pid, ["BTC-USD"])
      Process.sleep(50)

      state = :sys.get_state(pid)
      send(pid, {:stream_connected, state.websocket_pid})
      Process.sleep(50)

      # Manually fire the subscription timer
      send(pid, :send_subscriptions)
      Process.sleep(50)

      assert Process.alive?(pid)
      assert Connection.get_status(pid) == :connected
    end

    test "does nothing when not connected" do
      pid = start_connection()
      # Don't connect, just send the message
      send(pid, :send_subscriptions)
      Process.sleep(50)

      assert Process.alive?(pid)
      assert Connection.get_status(pid) == :disconnected
    end
  end

  # ============================================================================
  # JWT Refresh Tests
  # ============================================================================

  describe ":refresh_jwt handler" do
    test "refreshes JWT when connected" do
      pid = start_connection()
      Connection.subscribe(pid, ["BTC-USD"])
      Process.sleep(50)

      state = :sys.get_state(pid)
      send(pid, {:stream_connected, state.websocket_pid})
      Process.sleep(100)

      send(pid, :refresh_jwt)
      Process.sleep(50)

      assert Process.alive?(pid)
      assert Connection.get_status(pid) == :connected
    end

    test "does nothing when not connected" do
      pid = start_connection()
      send(pid, :refresh_jwt)
      Process.sleep(50)

      assert Process.alive?(pid)
      assert Connection.get_status(pid) == :disconnected
    end
  end

  # ============================================================================
  # Reconnection Tests
  # ============================================================================

  describe "reconnection" do
    test "schedules reconnect on disconnect" do
      pid = start_connection()
      Connection.subscribe(pid, ["BTC-USD"])
      Process.sleep(50)

      state = :sys.get_state(pid)
      ws_pid = state.websocket_pid

      # Simulate connection then disconnect
      send(pid, {:stream_connected, ws_pid})
      Process.sleep(50)
      send(pid, {:stream_disconnected, ws_pid, :closed})
      Process.sleep(50)

      assert Connection.get_status(pid) == :reconnecting
    end

    test "stops reconnecting after max attempts" do
      pid = start_connection()
      Connection.subscribe(pid, ["BTC-USD"])
      Process.sleep(50)

      # Set reconnect_attempts to max (10) via repeated disconnects
      # Using :sys.replace_state to set it directly
      :sys.replace_state(pid, fn state ->
        %{state | reconnect_attempts: 10, status: :connected}
      end)

      state = :sys.get_state(pid)
      ws_pid = state.websocket_pid

      send(pid, {:stream_disconnected, ws_pid, :closed})
      Process.sleep(50)

      assert Connection.get_status(pid) == :disconnected
    end
  end

  describe "reconnect/1" do
    test "triggers a manual reconnect" do
      pid = start_connection()
      Connection.subscribe(pid, ["BTC-USD"])
      Process.sleep(50)

      Connection.reconnect(pid)
      Process.sleep(50)

      assert Connection.get_status(pid) in [:reconnecting, :connecting, :connected]
    end
  end

  # ============================================================================
  # Connection Error Tests
  # ============================================================================

  describe "do_connect error path" do
    test "schedules reconnect when start_link fails" do
      # Start connection first (init doesn't call start_link)
      pid = start_connection()

      # Set expect and allow GenServer to use it
      expect(ExCoinbase.WebSocket.Client, :start_link, fn _url, _parent ->
        {:error, :connection_refused}
      end)

      Mimic.allow(ExCoinbase.WebSocket.Client, self(), pid)

      # Subscribe triggers do_connect in the GenServer process
      Connection.subscribe(pid, ["BTC-USD"])
      Process.sleep(50)

      assert Connection.get_status(pid) == :reconnecting
    end
  end

  # ============================================================================
  # Unexpected Message Tests
  # ============================================================================

  describe "unexpected messages" do
    test "handles unexpected messages without crashing" do
      pid = start_connection()
      send(pid, {:unexpected, :message})
      Process.sleep(50)
      assert Process.alive?(pid)
    end
  end

  # ============================================================================
  # Stop Tests
  # ============================================================================

  describe "stop/1" do
    test "stops the GenServer gracefully" do
      pid = start_connection()
      assert Process.alive?(pid)

      Connection.stop(pid)
      Process.sleep(50)
      refute Process.alive?(pid)
    end

    test "stops gracefully when connected with products" do
      pid = start_connection()
      Connection.subscribe(pid, ["BTC-USD"])
      Process.sleep(50)

      state = :sys.get_state(pid)
      send(pid, {:stream_connected, state.websocket_pid})
      Process.sleep(100)

      Connection.stop(pid)
      Process.sleep(50)
      refute Process.alive?(pid)
    end
  end
end
