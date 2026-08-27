defmodule ExCoinbase.OrdersTest do
  use ExUnit.Case, async: true

  alias ExCoinbase.Fixtures
  alias ExCoinbase.Orders

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

  describe "limit_order_ioc/5" do
    test "returns success" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_create_order_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, _} = Orders.limit_order_ioc(client, "BTC-USD", "BUY", "0.001", "50000")
    end
  end

  describe "limit_order_gtd/6" do
    test "returns success" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_create_order_response())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, _} =
               Orders.limit_order_gtd(
                 client,
                 "BTC-USD",
                 "BUY",
                 "0.001",
                 "50000",
                 "2024-12-31T23:59:59Z"
               )
    end
  end

  describe "limit_order_fok/5" do
    test "returns success" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_create_order_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, _} = Orders.limit_order_fok(client, "BTC-USD", "BUY", "0.001", "50000")
    end
  end

  describe "stop_limit_order_gtd/7" do
    test "returns success" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_create_order_response())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, _} =
               Orders.stop_limit_order_gtd(
                 client,
                 "BTC-USD",
                 "SELL",
                 "0.001",
                 "49000",
                 "48000",
                 "2024-12-31T23:59:59Z"
               )
    end
  end

  describe "edit_order/3" do
    test "returns success when editing price" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_edit_order_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"success" => true}} = Orders.edit_order(client, "order-123", price: "51000")
    end

    test "returns success when editing size" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_edit_order_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"success" => true}} = Orders.edit_order(client, "order-123", size: "0.002")
    end

    test "returns success when editing both price and size" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_edit_order_response())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, _} =
               Orders.edit_order(client, "order-123", price: "51000", size: "0.002")
    end

    test "returns validation error when neither price nor size provided" do
      client = Fixtures.test_client(@stub_name)
      assert {:error, {:validation_error, errors}} = Orders.edit_order(client, "order-123")
      assert "at least one of price or size is required" in errors
    end
  end

  describe "edit_order_preview/3" do
    test "returns preview data for price edit" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_edit_order_preview_response())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, %{"slippage" => _}} =
               Orders.edit_order_preview(client, "order-123", price: "51000")
    end

    test "returns validation error when neither price nor size provided" do
      client = Fixtures.test_client(@stub_name)

      assert {:error, {:validation_error, _}} =
               Orders.edit_order_preview(client, "order-123")
    end
  end

  describe "preview_order/2" do
    test "returns preview for valid order" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_preview_order_response())
      end)

      client = Fixtures.test_client(@stub_name)

      params = %{
        product_id: "BTC-USD",
        side: "BUY",
        order_configuration: %{market_market_ioc: %{quote_size: "100"}}
      }

      assert {:ok, %{"commission_total" => _}} = Orders.preview_order(client, params)
    end

    test "returns validation error for invalid params" do
      client = Fixtures.test_client(@stub_name)
      assert {:error, {:validation_error, _}} = Orders.preview_order(client, %{})
    end
  end

  describe "close_position/4" do
    test "closes position fully" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_close_position_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"success" => true}} = Orders.close_position(client, "close-123", "BTC-USD")
    end

    test "closes position partially with size" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_close_position_response())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, %{"success" => true}} =
               Orders.close_position(client, "close-123", "BTC-USD", size: "0.5")
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

  describe "request encoding (0.2.0 API sync)" do
    test "limit_order_ioc sends sor_limit_ioc" do
      Req.Test.expect(@stub_name, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)

        assert %{"sor_limit_ioc" => %{"base_size" => "0.1", "limit_price" => "100"}} =
                 params["order_configuration"]

        refute Map.has_key?(params["order_configuration"], "limit_limit_ioc")
        Req.Test.json(conn, Fixtures.sample_create_order_response())
      end)

      assert {:ok, _} =
               Orders.limit_order_ioc(
                 Fixtures.test_client(@stub_name),
                 "BTC-USD",
                 "BUY",
                 "0.1",
                 "100"
               )
    end

    test "market_order_fok sends market_market_fok" do
      Req.Test.expect(@stub_name, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        assert %{"market_market_fok" => %{"base_size" => "1"}} =
                 Jason.decode!(body)["order_configuration"]

        Req.Test.json(conn, Fixtures.sample_create_order_response())
      end)

      assert {:ok, _} =
               Orders.market_order_fok(
                 Fixtures.test_client(@stub_name),
                 "BTC-PERP-INTX",
                 "SELL",
                 "1"
               )
    end

    test "twap_order_gtd builds twap_limit_gtd config" do
      Req.Test.expect(@stub_name, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        config = Jason.decode!(body)["order_configuration"]["twap_limit_gtd"]

        assert config == %{
                 "base_size" => "1",
                 "limit_price" => "50000",
                 "start_time" => "2026-09-01T00:00:00Z",
                 "end_time" => "2026-09-01T01:00:00Z",
                 "number_buckets" => "6",
                 "bucket_size" => "0.1666",
                 "bucket_duration" => "600s"
               }

        Req.Test.json(conn, Fixtures.sample_create_order_response())
      end)

      assert {:ok, _} =
               Orders.twap_order_gtd(
                 Fixtures.test_client(@stub_name),
                 "BTC-USD",
                 "BUY",
                 %{base_size: "1"},
                 "50000",
                 start_time: "2026-09-01T00:00:00Z",
                 end_time: "2026-09-01T01:00:00Z",
                 number_buckets: "6",
                 bucket_size: "0.1666",
                 bucket_duration: "600s"
               )
    end

    test "scaled_order_gtc builds scaled_limit_gtc config" do
      Req.Test.expect(@stub_name, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        config = Jason.decode!(body)["order_configuration"]["scaled_limit_gtc"]

        assert config == %{
                 "quote_size" => "1000",
                 "num_orders" => "5",
                 "min_price" => "45000",
                 "max_price" => "49000"
               }

        Req.Test.json(conn, Fixtures.sample_create_order_response())
      end)

      assert {:ok, _} =
               Orders.scaled_order_gtc(
                 Fixtures.test_client(@stub_name),
                 "BTC-USD",
                 "BUY",
                 %{quote_size: "1000"},
                 num_orders: "5",
                 min_price: "45000",
                 max_price: "49000"
               )
    end

    test "create_order forwards prediction/equity/sor/cost-basis metadata and a caller client_order_id" do
      Req.Test.expect(@stub_name, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)
        assert params["client_order_id"] == "my-id-1"
        assert params["prediction_metadata"] == %{"prediction_side" => "PREDICTION_SIDE_YES"}
        assert params["sor_preference"] == "SOR_DISABLED"
        assert params["cost_basis_method"] == "COST_BASIS_METHOD_FIFO"
        assert params["preview_id"] == "prev-1"

        assert params["equity_order_metadata"] == %{
                 "equity_trading_session" => "EQUITY_TRADING_SESSION_NORMAL"
               }

        Req.Test.json(conn, Fixtures.sample_create_order_response())
      end)

      params = %{
        client_order_id: "my-id-1",
        product_id: "KXBTC-26SEP-100K",
        side: "BUY",
        order_configuration: %{market_market_ioc: %{quote_size: "10"}},
        prediction_metadata: %{prediction_side: "PREDICTION_SIDE_YES"},
        sor_preference: "SOR_DISABLED",
        cost_basis_method: "COST_BASIS_METHOD_FIFO",
        preview_id: "prev-1",
        equity_order_metadata: %{equity_trading_session: "EQUITY_TRADING_SESSION_NORMAL"}
      }

      assert {:ok, _} = Orders.create_order(Fixtures.test_client(@stub_name), params)
    end

    test "list_orders encodes list filters as repeated keys" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.request_path == "/api/v3/brokerage/orders/historical/batch"

        assert conn.query_string ==
                 "product_ids=BTC-USD&product_ids=ETH-USD&order_status=OPEN&order_status=FILLED&limit=5"

        Req.Test.json(conn, %{"orders" => []})
      end)

      assert {:ok, _} =
               Orders.list_orders(Fixtures.test_client(@stub_name),
                 product_ids: ["BTC-USD", "ETH-USD"],
                 order_status: ["OPEN", "FILLED"],
                 limit: 5,
                 product_id: "IGNORED"
               )
    end

    test "list_fills encodes order_ids/product_ids as repeated keys" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.query_string == "order_ids=o1&order_ids=o2&product_ids=BTC-USD"
        Req.Test.json(conn, %{"fills" => []})
      end)

      assert {:ok, _} =
               Orders.list_fills(Fixtures.test_client(@stub_name),
                 order_ids: ["o1", "o2"],
                 product_ids: ["BTC-USD"]
               )
    end

    test "exposes the new enum helpers" do
      assert "PREDICTION_SIDE_YES" in Orders.valid_prediction_sides()
      assert "SOR_ENABLED" in Orders.valid_sor_preferences()
      assert "COST_BASIS_METHOD_FIFO" in Orders.valid_cost_basis_methods()
      assert "TWAP" in Orders.valid_order_types()
    end
  end
end
