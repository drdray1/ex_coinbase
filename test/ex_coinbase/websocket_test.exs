defmodule ExCoinbase.WebSocketTest do
  use ExUnit.Case, async: true

  alias ExCoinbase.Fixtures
  alias ExCoinbase.WebSocket

  describe "build_subscribe_message/3" do
    test "builds user channel subscribe message with JWT" do
      message = WebSocket.build_subscribe_message("user", ["BTC-USD"], "jwt_token")

      assert message["type"] == "subscribe"
      assert message["channel"] == "user"
      assert message["product_ids"] == ["BTC-USD"]
      assert message["jwt"] == "jwt_token"
    end

    test "builds heartbeat subscribe message without JWT" do
      message = WebSocket.build_subscribe_message("heartbeats", [], nil)

      assert message["type"] == "subscribe"
      assert message["channel"] == "heartbeats"
      refute Map.has_key?(message, "product_ids")
      refute Map.has_key?(message, "jwt")
    end
  end

  describe "build_unsubscribe_message/2" do
    test "builds unsubscribe message" do
      message = WebSocket.build_unsubscribe_message("user", ["BTC-USD"])

      assert message["type"] == "unsubscribe"
      assert message["channel"] == "user"
      assert message["product_ids"] == ["BTC-USD"]
    end
  end

  describe "encode_message/1" do
    test "encodes message to JSON" do
      message = %{"type" => "subscribe", "channel" => "heartbeats"}
      {:ok, json} = WebSocket.encode_message(message)
      decoded = Jason.decode!(json)
      assert decoded["type"] == "subscribe"
    end
  end

  describe "parse_event/1" do
    test "parses user order event" do
      json = Jason.encode!(Fixtures.sample_user_event())
      {:ok, :user, event} = WebSocket.parse_event(json)

      assert %WebSocket.UserOrderEvent{} = event
      assert event.channel == "user"
      assert length(event.events) == 1
    end

    test "parses heartbeat event" do
      json = Jason.encode!(Fixtures.sample_heartbeat_event())
      {:ok, :heartbeat, event} = WebSocket.parse_event(json)

      assert %WebSocket.HeartbeatEvent{} = event
      assert event.channel == "heartbeats"
      assert event.heartbeat_counter == 1
    end

    test "parses error event" do
      json = Jason.encode!(Fixtures.sample_error_event())
      {:error, {:server_error, message}} = WebSocket.parse_event(json)
      assert message == "Invalid product ID"
    end

    test "parses subscriptions event" do
      json = Jason.encode!(Fixtures.sample_subscriptions_event())
      {:ok, :subscriptions, _data} = WebSocket.parse_event(json)
    end

    test "returns error for invalid JSON" do
      assert {:error, :invalid_json} = WebSocket.parse_event("not json")
    end

    test "returns error for unknown message format" do
      json = Jason.encode!(%{"something" => "unknown"})
      assert {:error, :unknown_message_format} = WebSocket.parse_event(json)
    end
  end

  describe "parse_user_order_event/1" do
    test "parses snapshot event with orders" do
      data = Fixtures.sample_user_event()
      event = WebSocket.parse_user_order_event(data)

      assert event.channel == "user"
      assert event.sequence_num == 400
      assert length(event.events) == 1

      [order_update] = event.events
      assert %WebSocket.OrderUpdate{} = order_update
      assert order_update.order_id == "order-123"
      assert order_update.product_id == "BTC-USD"
      assert order_update.side == "BUY"
      assert order_update.status == "OPEN"
    end

    test "handles empty orders in snapshot" do
      data = %{
        "channel" => "user",
        "events" => [%{"type" => "snapshot", "orders" => []}]
      }

      event = WebSocket.parse_user_order_event(data)
      assert event.events == []
    end
  end

  describe "map_order_status/1" do
    test "maps known statuses" do
      assert WebSocket.map_order_status("FILLED") == "filled"
      assert WebSocket.map_order_status("CANCELLED") == "cancelled"
      assert WebSocket.map_order_status("PENDING") == "submitted"
      assert WebSocket.map_order_status("OPEN") == "submitted"
      assert WebSocket.map_order_status("EXPIRED") == "expired"
      assert WebSocket.map_order_status("FAILED") == "rejected"
      assert WebSocket.map_order_status("CANCEL_QUEUED") == "cancelling"
    end

    test "downcases unknown statuses" do
      assert WebSocket.map_order_status("SOME_NEW_STATUS") == "some_new_status"
    end
  end

  describe "jwt_refresh_interval_ms/0" do
    test "returns 100 seconds in ms (120 - 20 buffer)" do
      assert WebSocket.jwt_refresh_interval_ms() == 100_000
    end
  end

  describe "build_authenticated_subscribe/3" do
    @test_api_key "organizations/test-org-123/apiKeys/test-key-456"
    @test_private_key """
    -----BEGIN EC PRIVATE KEY-----
    MHcCAQEEIJu/Ze6KwFX6kqjf0YTCwuFtFwcaIA6NfRc2XaioC8DdoAoGCCqGSM49
    AwEHoUQDQgAE6ob5+ow9MXBF4R28xeIzj5djEWB9OM681bQ2IlqjV4LJAKdRyPRX
    7cjqMZo/TspePuKrd936h3l17oeU4qlgHw==
    -----END EC PRIVATE KEY-----
    """

    test "returns {:ok, message} with JWT for valid credentials" do
      assert {:ok, message} =
               WebSocket.build_authenticated_subscribe(@test_api_key, @test_private_key, [
                 "BTC-USD"
               ])

      assert message["type"] == "subscribe"
      assert message["channel"] == "user"
      assert message["product_ids"] == ["BTC-USD"]
      assert is_binary(message["jwt"])
    end

    test "returns {:error, _} for invalid private key" do
      assert {:error, _} =
               WebSocket.build_authenticated_subscribe(@test_api_key, "invalid", ["BTC-USD"])
    end
  end

  describe "parse_event_from_map/1" do
    test "returns {:error, {:unknown_channel, channel}} for unknown channel" do
      data = %{"channel" => "unknown_channel", "events" => []}

      assert {:error, {:unknown_channel, "unknown_channel"}} =
               WebSocket.parse_event_from_map(data)
    end

    test "handles error event without message key" do
      data = %{"type" => "error", "reason" => "Something went wrong"}

      assert {:error, {:server_error, "Something went wrong"}} =
               WebSocket.parse_event_from_map(data)
    end

    test "returns unknown error for error event without message or reason" do
      data = %{"type" => "error"}
      assert {:error, {:server_error, "Unknown error"}} = WebSocket.parse_event_from_map(data)
    end
  end

  describe "parse_order_update/1" do
    test "handles single order update event" do
      data = %{
        "type" => "update",
        "order" => %{
          "order_id" => "order-456",
          "product_id" => "ETH-USD",
          "side" => "SELL",
          "status" => "FILLED"
        }
      }

      updates = WebSocket.parse_order_update(data)
      assert length(updates) == 1
      [update] = updates
      assert update.order_id == "order-456"
      assert update.type == "update"
    end

    test "handles fallback when no orders or order key" do
      data = %{"type" => "update", "order_id" => "order-789", "product_id" => "BTC-USD"}
      updates = WebSocket.parse_order_update(data)
      assert length(updates) == 1
      [update] = updates
      assert update.order_id == "order-789"
    end
  end

  describe "parse_heartbeat_event/1" do
    test "handles event with no events list" do
      data = %{"channel" => "heartbeats", "timestamp" => "2024-01-01T00:00:00Z"}
      event = WebSocket.parse_heartbeat_event(data)
      assert %WebSocket.HeartbeatEvent{} = event
      assert event.current_time == nil
      assert event.heartbeat_counter == nil
    end
  end

  describe "jwt_expiry_seconds/0" do
    test "returns 120" do
      assert WebSocket.jwt_expiry_seconds() == 120
    end
  end

  describe "jwt_refresh_buffer_seconds/0" do
    test "returns 20" do
      assert WebSocket.jwt_refresh_buffer_seconds() == 20
    end
  end

  describe "websocket_user_url/0" do
    test "returns user websocket URL" do
      url = WebSocket.websocket_user_url()
      assert String.contains?(url, "advanced-trade-ws-user.coinbase.com")
    end
  end

  # ============================================================================
  # Market Data Event Parsing
  # ============================================================================

  describe "parse_level2_event/1" do
    test "parses level2 snapshot event" do
      data = Fixtures.sample_level2_event()
      event = WebSocket.parse_level2_event(data)

      assert %WebSocket.Level2Event{} = event
      assert event.channel == "l2_data"
      assert event.product_id == "BTC-USD"
      assert length(event.updates) == 2
    end

    test "handles empty events list" do
      data = %{"channel" => "l2_data", "events" => []}
      event = WebSocket.parse_level2_event(data)
      assert event.product_id == nil
      assert event.updates == []
    end
  end

  describe "parse_ticker_event/1" do
    test "parses ticker snapshot event" do
      data = Fixtures.sample_ticker_event()
      event = WebSocket.parse_ticker_event(data)

      assert %WebSocket.TickerEvent{} = event
      assert event.channel == "ticker"
      assert length(event.tickers) == 1
      [ticker] = event.tickers
      assert ticker["product_id"] == "BTC-USD"
      assert ticker["price"] == "50000.00"
    end
  end

  describe "parse_ticker_batch_event/1" do
    test "parses ticker_batch event" do
      data = Fixtures.sample_ticker_batch_event()
      event = WebSocket.parse_ticker_batch_event(data)

      assert %WebSocket.TickerBatchEvent{} = event
      assert event.channel == "ticker_batch"
      assert length(event.tickers) == 2
    end
  end

  describe "parse_market_trades_event/1" do
    test "parses market_trades event" do
      data = Fixtures.sample_market_trades_ws_event()
      event = WebSocket.parse_market_trades_event(data)

      assert %WebSocket.MarketTradesEvent{} = event
      assert event.channel == "market_trades"
      assert length(event.trades) == 1
      [trade] = event.trades
      assert trade["trade_id"] == "trade-1"
    end
  end

  describe "parse_event/1 with market data channels" do
    test "parses l2_data channel" do
      json = Jason.encode!(Fixtures.sample_level2_event())
      assert {:ok, :level2, %WebSocket.Level2Event{}} = WebSocket.parse_event(json)
    end

    test "parses ticker channel" do
      json = Jason.encode!(Fixtures.sample_ticker_event())
      assert {:ok, :ticker, %WebSocket.TickerEvent{}} = WebSocket.parse_event(json)
    end

    test "parses ticker_batch channel" do
      json = Jason.encode!(Fixtures.sample_ticker_batch_event())
      assert {:ok, :ticker_batch, %WebSocket.TickerBatchEvent{}} = WebSocket.parse_event(json)
    end

    test "parses market_trades channel" do
      json = Jason.encode!(Fixtures.sample_market_trades_ws_event())
      assert {:ok, :market_trades, %WebSocket.MarketTradesEvent{}} = WebSocket.parse_event(json)
    end
  end

  describe "valid_market_channels/0" do
    test "returns the four market data channels" do
      channels = WebSocket.valid_market_channels()
      assert "level2" in channels
      assert "ticker" in channels
      assert "ticker_batch" in channels
      assert "market_trades" in channels
    end
  end

  describe "websocket_url/0" do
    test "returns public websocket URL" do
      url = WebSocket.websocket_url()
      assert String.contains?(url, "advanced-trade-ws.coinbase.com")
    end
  end
end
