defmodule ExCoinbase.WebSocketTest do
  use ExUnit.Case, async: true

  alias ExCoinbase.WebSocket
  alias ExCoinbase.Fixtures

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
end
