defmodule ExCoinbase.OrdersTest do
  use ExUnit.Case, async: true

  alias ExCoinbase.Orders
  alias ExCoinbase.Fixtures

  @stub_name ExCoinbase.OrdersTest

  # ============================================================================
  # HTTP Endpoint Tests
  # ============================================================================

  describe "create_order/2" do
    test "returns success for valid order" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_create_order_response())
      end)

      client = Fixtures.test_client(@stub_name)

      params = %{
        product_id: "BTC-USD",
        side: "BUY",
        order_configuration: %{market_market_ioc: %{quote_size: "100"}}
      }

      assert {:ok, %{"success" => true}} = Orders.create_order(client, params)
    end

    test "returns validation error for missing product_id" do
      client = Fixtures.test_client(@stub_name)

      params = %{
        side: "BUY",
        order_configuration: %{market_market_ioc: %{quote_size: "100"}}
      }

      assert {:error, {:validation_error, errors}} = Orders.create_order(client, params)
      assert "product_id is required" in errors
    end
  end

  describe "market_order_quote/4" do
    test "returns success" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_create_order_response())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, %{"success" => true}} =
               Orders.market_order_quote(client, "BTC-USD", "BUY", "100")
    end
  end

  describe "market_order_base/4" do
    test "returns success" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_create_order_response())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, %{"success" => true}} =
               Orders.market_order_base(client, "BTC-USD", "BUY", "0.001")
    end
  end

  describe "limit_order_gtc/5" do
    test "returns success" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_create_order_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, _} = Orders.limit_order_gtc(client, "BTC-USD", "BUY", "0.001", "50000")
    end
  end

  describe "stop_limit_order_gtc/6" do
    test "returns success" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_create_order_response())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, _} =
               Orders.stop_limit_order_gtc(client, "BTC-USD", "SELL", "0.001", "49000", "48000")
    end
  end

  describe "bracket_order_gtc/7" do
    test "returns success" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_create_order_response())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, _} =
               Orders.bracket_order_gtc(
                 client,
                 "BTC-USD",
                 "BUY",
                 "0.01",
                 "45000",
                 "50000",
                 "43000"
               )
    end
  end

  describe "bracket_order_gtd/8" do
    test "returns success" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_create_order_response())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, _} =
               Orders.bracket_order_gtd(
                 client,
                 "BTC-USD",
                 "BUY",
                 "0.01",
                 "45000",
                 "50000",
                 "43000",
                 "2024-12-31T23:59:59Z"
               )
    end
  end

  describe "cancel_orders/2" do
    test "returns success" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_cancel_orders_response())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, %{"results" => results}} =
               Orders.cancel_orders(client, ["order-1", "order-2"])

      assert length(results) == 2
    end
  end

  describe "cancel_order/2" do
    test "returns success" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, %{"results" => [%{"success" => true, "order_id" => "order-1"}]})
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, %{"results" => [%{"success" => true}]}} =
               Orders.cancel_order(client, "order-1")
    end
  end

  describe "list_orders/2" do
    test "returns orders on success" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_orders_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"orders" => orders}} = Orders.list_orders(client)
      assert length(orders) == 2
    end
  end

  describe "get_order/2" do
    test "returns order on success" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_single_order_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"order" => order}} = Orders.get_order(client, "order-1")
      assert order["order_id"] == "order-1"
    end
  end

  describe "list_fills/2" do
    test "returns fills on success" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_fills_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"fills" => fills}} = Orders.list_fills(client)
      assert length(fills) == 1
    end
  end

  # ============================================================================
  # Pure Function Tests
  # ============================================================================

  describe "validate_order_params/1" do
    test "returns ok for valid params" do
      params = %{
        product_id: "BTC-USD",
        side: "BUY",
        order_configuration: %{market_market_ioc: %{quote_size: "100"}}
      }

      assert {:ok, ^params} = Orders.validate_order_params(params)
    end

    test "returns errors for missing required fields" do
      assert {:error, errors} = Orders.validate_order_params(%{})
      assert "product_id is required" in errors
      assert "side is required" in errors
      assert "order_configuration is required" in errors
    end

    test "validates side values" do
      params = %{
        product_id: "BTC-USD",
        side: "INVALID",
        order_configuration: %{market_market_ioc: %{quote_size: "100"}}
      }

      assert {:error, errors} = Orders.validate_order_params(params)
      assert Enum.any?(errors, &String.contains?(&1, "side must be one of"))
    end

    test "validates order_configuration is a map" do
      params = %{
        product_id: "BTC-USD",
        side: "BUY",
        order_configuration: "invalid"
      }

      assert {:error, errors} = Orders.validate_order_params(params)
      assert "order_configuration must be a map" in errors
    end

    test "validates order_configuration is not empty" do
      params = %{
        product_id: "BTC-USD",
        side: "BUY",
        order_configuration: %{}
      }

      assert {:error, errors} = Orders.validate_order_params(params)
      assert "order_configuration cannot be empty" in errors
    end

    test "returns error for non-map input" do
      assert {:error, ["params must be a map"]} = Orders.validate_order_params("invalid")
    end
  end

  describe "extract_orders/1" do
    test "extracts orders from valid response" do
      response = %{
        "orders" => [
          %{"order_id" => "order-1", "status" => "OPEN"},
          %{"order_id" => "order-2", "status" => "FILLED"}
        ]
      }

      orders = Orders.extract_orders(response)
      assert length(orders) == 2
    end

    test "returns empty list for missing orders" do
      assert Orders.extract_orders(%{}) == []
      assert Orders.extract_orders(nil) == []
    end
  end

  describe "extract_fills/1" do
    test "extracts fills from valid response" do
      response = %{
        "fills" => [
          %{"fill_id" => "fill-1", "order_id" => "order-1"}
        ]
      }

      fills = Orders.extract_fills(response)
      assert length(fills) == 1
    end

    test "returns empty list for missing fills" do
      assert Orders.extract_fills(%{}) == []
    end
  end

  describe "extract_order/1" do
    test "extracts single order" do
      response = %{"order" => %{"order_id" => "order-1", "status" => "FILLED"}}
      order = Orders.extract_order(response)
      assert order["order_id"] == "order-1"
    end

    test "returns nil for missing order" do
      assert Orders.extract_order(%{}) == nil
    end
  end

  describe "filter_by_status/2" do
    test "filters orders by status" do
      orders = [
        %{"order_id" => "1", "status" => "OPEN"},
        %{"order_id" => "2", "status" => "FILLED"},
        %{"order_id" => "3", "status" => "OPEN"}
      ]

      open_orders = Orders.filter_by_status(orders, "OPEN")
      assert length(open_orders) == 2
    end
  end

  describe "filter_by_product/2" do
    test "filters orders by product" do
      orders = [
        %{"order_id" => "1", "product_id" => "BTC-USD"},
        %{"order_id" => "2", "product_id" => "ETH-USD"},
        %{"order_id" => "3", "product_id" => "BTC-USD"}
      ]

      btc_orders = Orders.filter_by_product(orders, "BTC-USD")
      assert length(btc_orders) == 2
    end
  end

  describe "valid_sides/0" do
    test "returns BUY and SELL" do
      assert "BUY" in Orders.valid_sides()
      assert "SELL" in Orders.valid_sides()
    end
  end
end
