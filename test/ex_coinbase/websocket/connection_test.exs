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
  end
end
