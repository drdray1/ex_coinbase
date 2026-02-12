defmodule ExCoinbase.WebSocket.MarketDataConnectionTest do
  use ExUnit.Case, async: false
  use Mimic

  alias ExCoinbase.WebSocket.MarketDataConnection

  setup :verify_on_exit!

  setup do
    stub(ExCoinbase.WebSocket.Client, :start_link, fn _url, _parent ->
      {:ok, spawn(fn -> Process.sleep(:infinity) end)}
    end)

    stub(ExCoinbase.WebSocket.Client, :send_message, fn _pid, _msg -> :ok end)
    stub(ExCoinbase.WebSocket.Client, :close, fn _pid -> :ok end)

    stub(ExCoinbase.WebSocket, :websocket_url, fn ->
      "wss://test-market.example.com"
    end)

    stub(ExCoinbase.WebSocket, :build_subscribe_message, fn channel, _products, _jwt ->
      %{"type" => "subscribe", "channel" => channel}
    end)

    stub(ExCoinbase.WebSocket, :build_unsubscribe_message, fn channel, products ->
      %{"type" => "unsubscribe", "channel" => channel, "product_ids" => products}
    end)

    stub(ExCoinbase.WebSocket, :parse_event, fn _msg ->
      {:ok, :heartbeat, %ExCoinbase.WebSocket.HeartbeatEvent{channel: "heartbeats"}}
    end)

    :ok
  end

  defp start_connection(opts \\ []) do
    {:ok, pid} = MarketDataConnection.start_link(opts)

    on_exit(fn ->
      if Process.alive?(pid), do: MarketDataConnection.stop(pid)
    end)

    pid
  end

  # ============================================================================
  # Lifecycle Tests
  # ============================================================================

  describe "start_link/1" do
    test "starts GenServer without options" do
      pid = start_connection()
      assert Process.alive?(pid)
    end

    test "starts GenServer with name option" do
      pid = start_connection(name: :test_market_data)
      assert Process.alive?(pid)
      assert Process.whereis(:test_market_data) == pid
    end
  end

  # ============================================================================
  # Status Tests
  # ============================================================================

  describe "get_status/1" do
    test "returns :disconnected initially" do
      pid = start_connection()
      assert MarketDataConnection.get_status(pid) == :disconnected
    end
  end

  describe "get_info/1" do
    test "returns status, channels, and subscriber_count" do
      pid = start_connection()
      info = MarketDataConnection.get_info(pid)

      assert info.status == :disconnected
      assert info.channels == %{}
      assert info.subscriber_count == 0
    end
  end

  # ============================================================================
  # Subscription Tests
  # ============================================================================

  describe "subscribe/3" do
    test "triggers connection when channel products are added" do
      pid = start_connection()
      assert :ok = MarketDataConnection.subscribe(pid, "ticker", ["BTC-USD"])

      Process.sleep(50)
      status = MarketDataConnection.get_status(pid)
      assert status in [:connecting, :connected]
    end

    test "accumulates products for a channel" do
      pid = start_connection()
      MarketDataConnection.subscribe(pid, "ticker", ["BTC-USD"])
      MarketDataConnection.subscribe(pid, "ticker", ["ETH-USD"])

      Process.sleep(50)
      info = MarketDataConnection.get_info(pid)
      assert "BTC-USD" in info.channels["ticker"]
      assert "ETH-USD" in info.channels["ticker"]
    end

    test "supports multiple channels" do
      pid = start_connection()
      MarketDataConnection.subscribe(pid, "ticker", ["BTC-USD"])
      MarketDataConnection.subscribe(pid, "level2", ["ETH-USD"])

      Process.sleep(50)
      info = MarketDataConnection.get_info(pid)
      assert "BTC-USD" in info.channels["ticker"]
      assert "ETH-USD" in info.channels["level2"]
    end
  end

  describe "unsubscribe/3" do
    test "removes products from channel" do
      pid = start_connection()
      MarketDataConnection.subscribe(pid, "ticker", ["BTC-USD", "ETH-USD"])
      Process.sleep(50)

      MarketDataConnection.unsubscribe(pid, "ticker", ["ETH-USD"])
      info = MarketDataConnection.get_info(pid)

      assert "BTC-USD" in info.channels["ticker"]
      refute "ETH-USD" in info.channels["ticker"]
    end

    test "removes channel entirely when all products removed" do
      pid = start_connection()
      MarketDataConnection.subscribe(pid, "ticker", ["BTC-USD"])
      Process.sleep(50)

      MarketDataConnection.unsubscribe(pid, "ticker", ["BTC-USD"])
      info = MarketDataConnection.get_info(pid)

      refute Map.has_key?(info.channels, "ticker")
    end
  end

  # ============================================================================
  # Subscriber Management Tests
  # ============================================================================

  describe "add_subscriber/2 and remove_subscriber/2" do
    test "adds and removes subscriber" do
      pid = start_connection()

      MarketDataConnection.add_subscriber(pid, self())
      Process.sleep(50)
      assert MarketDataConnection.get_info(pid).subscriber_count == 1

      MarketDataConnection.remove_subscriber(pid, self())
      Process.sleep(50)
      assert MarketDataConnection.get_info(pid).subscriber_count == 0
    end

    test "auto-removes subscriber on process exit" do
      pid = start_connection()

      subscriber = spawn(fn -> Process.sleep(:infinity) end)
      MarketDataConnection.add_subscriber(pid, subscriber)
      Process.sleep(50)
      assert MarketDataConnection.get_info(pid).subscriber_count == 1

      Process.exit(subscriber, :kill)
      Process.sleep(50)
      assert MarketDataConnection.get_info(pid).subscriber_count == 0
    end
  end

  # ============================================================================
  # Event Broadcasting Tests
  # ============================================================================

  describe "stream event handling" do
    test "broadcasts ticker events to subscribers" do
      pid = start_connection()
      MarketDataConnection.add_subscriber(pid, self())
      Process.sleep(50)

      fake_ws_pid = spawn(fn -> Process.sleep(:infinity) end)

      :sys.replace_state(pid, fn state ->
        %{
          state
          | websocket_pid: fake_ws_pid,
            status: :connected,
            channel_subscriptions: %{"ticker" => MapSet.new(["BTC-USD"])}
        }
      end)

      msg =
        Jason.encode!(%{
          "channel" => "ticker",
          "client_id" => "c1",
          "timestamp" => "2024-01-01T00:00:00Z",
          "sequence_num" => 1,
          "events" => [
            %{"type" => "ticker", "tickers" => [%{"product_id" => "BTC-USD", "price" => "50000"}]}
          ]
        })

      send(pid, {:stream_message, fake_ws_pid, msg})

      assert_receive {:coinbase_market_event, :ticker,
                      %ExCoinbase.WebSocket.TickerEvent{
                        channel: "ticker",
                        tickers: [%{"product_id" => "BTC-USD", "price" => "50000"}]
                      }},
                     500
    end

    test "broadcasts level2 events to subscribers" do
      pid = start_connection()
      MarketDataConnection.add_subscriber(pid, self())
      Process.sleep(50)

      fake_ws_pid = spawn(fn -> Process.sleep(:infinity) end)

      :sys.replace_state(pid, fn state ->
        %{
          state
          | websocket_pid: fake_ws_pid,
            status: :connected,
            channel_subscriptions: %{"level2" => MapSet.new(["BTC-USD"])}
        }
      end)

      msg =
        Jason.encode!(%{
          "channel" => "l2_data",
          "client_id" => "c1",
          "timestamp" => "2024-01-01T00:00:00Z",
          "sequence_num" => 1,
          "events" => [
            %{
              "product_id" => "BTC-USD",
              "type" => "snapshot",
              "updates" => [%{"side" => "bid", "price_level" => "50000", "new_quantity" => "1.5"}]
            }
          ]
        })

      send(pid, {:stream_message, fake_ws_pid, msg})

      assert_receive {:coinbase_market_event, :level2,
                      %ExCoinbase.WebSocket.Level2Event{
                        channel: "l2_data",
                        product_id: "BTC-USD",
                        updates: [
                          %{"side" => "bid", "price_level" => "50000", "new_quantity" => "1.5"}
                        ]
                      }},
                     500
    end

    test "broadcasts market_trades events to subscribers" do
      pid = start_connection()
      MarketDataConnection.add_subscriber(pid, self())
      Process.sleep(50)

      fake_ws_pid = spawn(fn -> Process.sleep(:infinity) end)

      :sys.replace_state(pid, fn state ->
        %{
          state
          | websocket_pid: fake_ws_pid,
            status: :connected,
            channel_subscriptions: %{"market_trades" => MapSet.new(["BTC-USD"])}
        }
      end)

      msg =
        Jason.encode!(%{
          "channel" => "market_trades",
          "client_id" => "c1",
          "timestamp" => "2024-01-01T00:00:00Z",
          "sequence_num" => 1,
          "events" => [
            %{
              "type" => "snapshot",
              "trades" => [%{"trade_id" => "t1", "product_id" => "BTC-USD"}]
            }
          ]
        })

      send(pid, {:stream_message, fake_ws_pid, msg})

      assert_receive {:coinbase_market_event, :market_trades,
                      %ExCoinbase.WebSocket.MarketTradesEvent{
                        channel: "market_trades",
                        trades: [%{"trade_id" => "t1", "product_id" => "BTC-USD"}]
                      }},
                     500
    end

    test "handles heartbeat messages without broadcasting" do
      pid = start_connection()
      MarketDataConnection.add_subscriber(pid, self())
      Process.sleep(50)

      fake_ws_pid = spawn(fn -> Process.sleep(:infinity) end)

      :sys.replace_state(pid, fn state ->
        %{
          state
          | websocket_pid: fake_ws_pid,
            status: :connected,
            channel_subscriptions: %{"ticker" => MapSet.new(["BTC-USD"])}
        }
      end)

      msg =
        Jason.encode!(%{
          "channel" => "heartbeats",
          "client_id" => "c1",
          "timestamp" => "2024-01-01T00:00:00Z",
          "sequence_num" => 1,
          "events" => [%{"current_time" => "2024-01-01T00:00:00Z", "heartbeat_counter" => "1"}]
        })

      send(pid, {:stream_message, fake_ws_pid, msg})
      Process.sleep(50)

      refute_receive {:coinbase_market_event, _, _}
    end

    test "handles subscriptions messages without crashing" do
      pid = start_connection()
      Process.sleep(50)

      fake_ws_pid = spawn(fn -> Process.sleep(:infinity) end)

      :sys.replace_state(pid, fn state ->
        %{
          state
          | websocket_pid: fake_ws_pid,
            status: :connected,
            channel_subscriptions: %{"ticker" => MapSet.new(["BTC-USD"])}
        }
      end)

      msg =
        Jason.encode!(%{
          "channel" => "subscriptions",
          "timestamp" => "2024-01-01T00:00:00Z",
          "events" => [%{"subscriptions" => %{"ticker" => ["BTC-USD"]}}]
        })

      send(pid, {:stream_message, fake_ws_pid, msg})
      Process.sleep(50)

      assert Process.alive?(pid)
    end

    test "handles server error messages without crashing" do
      pid = start_connection()
      Process.sleep(50)

      fake_ws_pid = spawn(fn -> Process.sleep(:infinity) end)

      :sys.replace_state(pid, fn state ->
        %{
          state
          | websocket_pid: fake_ws_pid,
            status: :connected,
            channel_subscriptions: %{"ticker" => MapSet.new(["BTC-USD"])}
        }
      end)

      msg = Jason.encode!(%{"type" => "error", "message" => "Something went wrong"})

      send(pid, {:stream_message, fake_ws_pid, msg})
      Process.sleep(50)

      assert Process.alive?(pid)
    end

    test "handles parse errors without crashing" do
      pid = start_connection()
      Process.sleep(50)

      fake_ws_pid = spawn(fn -> Process.sleep(:infinity) end)

      :sys.replace_state(pid, fn state ->
        %{
          state
          | websocket_pid: fake_ws_pid,
            status: :connected,
            channel_subscriptions: %{"ticker" => MapSet.new(["BTC-USD"])}
        }
      end)

      send(pid, {:stream_message, fake_ws_pid, "bad data"})
      Process.sleep(50)

      assert Process.alive?(pid)
    end
  end

  # ============================================================================
  # Send Subscriptions Handler Tests
  # ============================================================================

  describe ":send_subscriptions handler" do
    test "sends subscriptions for all channels when connected" do
      pid = start_connection()
      MarketDataConnection.subscribe(pid, "ticker", ["BTC-USD"])
      MarketDataConnection.subscribe(pid, "level2", ["ETH-USD"])
      Process.sleep(50)

      state = :sys.get_state(pid)
      send(pid, {:stream_connected, state.websocket_pid})
      Process.sleep(50)

      send(pid, :send_subscriptions)
      Process.sleep(50)

      assert Process.alive?(pid)
      assert MarketDataConnection.get_status(pid) == :connected
    end

    test "does nothing when not connected" do
      pid = start_connection()
      send(pid, :send_subscriptions)
      Process.sleep(50)

      assert Process.alive?(pid)
      assert MarketDataConnection.get_status(pid) == :disconnected
    end
  end

  # ============================================================================
  # Reconnection Tests
  # ============================================================================

  describe "reconnection" do
    test "schedules reconnect on disconnect" do
      pid = start_connection()
      MarketDataConnection.subscribe(pid, "ticker", ["BTC-USD"])
      Process.sleep(50)

      state = :sys.get_state(pid)
      ws_pid = state.websocket_pid

      send(pid, {:stream_connected, ws_pid})
      Process.sleep(50)
      send(pid, {:stream_disconnected, ws_pid, :closed})
      Process.sleep(50)

      assert MarketDataConnection.get_status(pid) == :reconnecting
    end

    test "stops reconnecting after max attempts" do
      pid = start_connection()
      MarketDataConnection.subscribe(pid, "ticker", ["BTC-USD"])
      Process.sleep(50)

      :sys.replace_state(pid, fn state ->
        %{state | reconnect_attempts: 10, status: :connected}
      end)

      state = :sys.get_state(pid)
      ws_pid = state.websocket_pid

      send(pid, {:stream_disconnected, ws_pid, :closed})
      Process.sleep(50)

      assert MarketDataConnection.get_status(pid) == :disconnected
    end
  end

  describe "reconnect/1" do
    test "triggers a manual reconnect" do
      pid = start_connection()
      MarketDataConnection.subscribe(pid, "ticker", ["BTC-USD"])
      Process.sleep(50)

      MarketDataConnection.reconnect(pid)
      Process.sleep(50)

      assert MarketDataConnection.get_status(pid) in [:reconnecting, :connecting, :connected]
    end
  end

  # ============================================================================
  # Connection Error Tests
  # ============================================================================

  describe "do_connect error path" do
    test "schedules reconnect when start_link fails" do
      pid = start_connection()

      expect(ExCoinbase.WebSocket.Client, :start_link, fn _url, _parent ->
        {:error, :connection_refused}
      end)

      Mimic.allow(ExCoinbase.WebSocket.Client, self(), pid)

      MarketDataConnection.subscribe(pid, "ticker", ["BTC-USD"])
      Process.sleep(50)

      assert MarketDataConnection.get_status(pid) == :reconnecting
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

      MarketDataConnection.stop(pid)
      Process.sleep(50)
      refute Process.alive?(pid)
    end

    test "stops gracefully when connected with subscriptions" do
      pid = start_connection()
      MarketDataConnection.subscribe(pid, "ticker", ["BTC-USD"])
      MarketDataConnection.subscribe(pid, "level2", ["ETH-USD"])
      Process.sleep(50)

      state = :sys.get_state(pid)
      send(pid, {:stream_connected, state.websocket_pid})
      Process.sleep(100)

      MarketDataConnection.stop(pid)
      Process.sleep(50)
      refute Process.alive?(pid)
    end
  end
end
