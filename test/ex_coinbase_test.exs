defmodule ExCoinbaseTest do
  use ExUnit.Case, async: true

  alias ExCoinbase.Fixtures

  @stub_name ExCoinbaseTest

  # ============================================================================
  # Non-delegated functions
  # ============================================================================

  describe "parse_product_id/1" do
    test "parses valid product ID into base and quote" do
      assert {:ok, %{base: "BTC", quote: "USD"}} = ExCoinbase.parse_product_id("BTC-USD")
      assert {:ok, %{base: "ETH", quote: "EUR"}} = ExCoinbase.parse_product_id("ETH-EUR")
    end

    test "returns error for invalid product ID" do
      assert {:error, :invalid_format} = ExCoinbase.parse_product_id("BTCUSD")
      assert {:error, :invalid_format} = ExCoinbase.parse_product_id("")
    end
  end

  describe "build_product_id/2" do
    test "builds product ID from base and quote" do
      assert "BTC-USD" = ExCoinbase.build_product_id("BTC", "USD")
    end
  end

  describe "extract_account_id/1" do
    test "extracts account UUID from first account" do
      accounts = [%{"uuid" => "abc-123"}, %{"uuid" => "def-456"}]
      assert "abc-123" = ExCoinbase.extract_account_id(accounts)
    end

    test "returns nil for empty list" do
      assert nil == ExCoinbase.extract_account_id([])
    end
  end

  # ============================================================================
  # Client delegates
  # ============================================================================

  describe "new/3" do
    test "delegates to Client.new" do
      client = ExCoinbase.new(Fixtures.sample_api_key(), Fixtures.sample_private_key_pem())
      assert %Req.Request{} = client
    end
  end

  # ============================================================================
  # Account delegates
  # ============================================================================

  describe "list_accounts/2" do
    test "delegates to Accounts.list_accounts" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_accounts_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"accounts" => accounts}} = ExCoinbase.list_accounts(client)
      assert length(accounts) == 2
    end
  end

  describe "get_account/2" do
    test "delegates to Accounts.get_account" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_account_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"account" => _}} = ExCoinbase.get_account(client, "test-uuid")
    end
  end

  describe "extract_accounts/1" do
    test "delegates to Accounts.extract_accounts" do
      response = Fixtures.sample_accounts_response()
      accounts = ExCoinbase.extract_accounts(response)
      assert length(accounts) == 2
    end
  end

  describe "find_account_by_currency/2" do
    test "delegates to Accounts.find_by_currency" do
      accounts = ExCoinbase.extract_accounts(Fixtures.sample_accounts_response())
      found = ExCoinbase.find_account_by_currency(accounts, "BTC")
      assert found["currency"] == "BTC"
    end
  end

  # ============================================================================
  # Product delegates
  # ============================================================================

  describe "list_products/2" do
    test "delegates to Products.list_products" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_products_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"products" => products}} = ExCoinbase.list_products(client)
      assert length(products) == 2
    end
  end

  describe "get_product/2" do
    test "delegates to Products.get_product" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, %{"product_id" => "BTC-USD", "price" => "50000.00"})
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"product_id" => "BTC-USD"}} = ExCoinbase.get_product(client, "BTC-USD")
    end
  end

  describe "get_candles/3" do
    test "delegates to Products.get_candles" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_candles_response())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, %{"candles" => _}} =
               ExCoinbase.get_candles(client, "BTC-USD",
                 start: "2024-01-01T00:00:00Z",
                 end: "2024-01-02T00:00:00Z",
                 granularity: "ONE_HOUR"
               )
    end
  end

  describe "get_market_trades/3" do
    test "delegates to Products.get_market_trades" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_market_trades_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"trades" => _}} = ExCoinbase.get_market_trades(client, "BTC-USD")
    end
  end

  describe "get_best_bid_ask/2" do
    test "delegates to Products.get_best_bid_ask" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_best_bid_ask_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"pricebooks" => _}} = ExCoinbase.get_best_bid_ask(client, ["BTC-USD"])
    end
  end

  describe "get_product_book/3" do
    test "delegates to Products.get_product_book" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_product_book_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"pricebook" => _}} = ExCoinbase.get_product_book(client, "BTC-USD")
    end
  end

  describe "extract_products/1" do
    test "delegates to Products.extract_products" do
      response = Fixtures.sample_products_response()
      assert length(ExCoinbase.extract_products(response)) == 2
    end
  end

  describe "extract_candles/1" do
    test "delegates to Products.extract_candles" do
      response = Fixtures.sample_candles_response()
      assert length(ExCoinbase.extract_candles(response)) == 2
    end
  end

  describe "valid_granularities/0" do
    test "delegates to Products.valid_granularities" do
      granularities = ExCoinbase.valid_granularities()
      assert "ONE_HOUR" in granularities
      assert "ONE_DAY" in granularities
    end
  end

  # ============================================================================
  # Order delegates
  # ============================================================================

  describe "create_order/2" do
    test "delegates to Orders.create_order" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_create_order_response())
      end)

      client = Fixtures.test_client(@stub_name)

      params = %{
        product_id: "BTC-USD",
        side: "BUY",
        order_configuration: %{market_market_ioc: %{quote_size: "100"}}
      }

      assert {:ok, %{"success" => true}} = ExCoinbase.create_order(client, params)
    end
  end

  describe "market_order_quote/4" do
    test "delegates to Orders.market_order_quote" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_create_order_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, _} = ExCoinbase.market_order_quote(client, "BTC-USD", "BUY", "100")
    end
  end

  describe "market_order_base/4" do
    test "delegates to Orders.market_order_base" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_create_order_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, _} = ExCoinbase.market_order_base(client, "BTC-USD", "BUY", "0.001")
    end
  end

  describe "limit_order_gtc/5" do
    test "delegates to Orders.limit_order_gtc" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_create_order_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, _} = ExCoinbase.limit_order_gtc(client, "BTC-USD", "BUY", "0.001", "50000")
    end
  end

  describe "stop_limit_order_gtc/6" do
    test "delegates to Orders.stop_limit_order_gtc" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_create_order_response())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, _} =
               ExCoinbase.stop_limit_order_gtc(
                 client,
                 "BTC-USD",
                 "SELL",
                 "0.001",
                 "49000",
                 "48000"
               )
    end
  end

  describe "bracket_order_gtc/7" do
    test "delegates to Orders.bracket_order_gtc" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_create_order_response())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, _} =
               ExCoinbase.bracket_order_gtc(
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
    test "delegates to Orders.bracket_order_gtd" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_create_order_response())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, _} =
               ExCoinbase.bracket_order_gtd(
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
    test "delegates to Orders.limit_order_ioc" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_create_order_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, _} = ExCoinbase.limit_order_ioc(client, "BTC-USD", "BUY", "0.001", "50000")
    end
  end

  describe "limit_order_gtd/6" do
    test "delegates to Orders.limit_order_gtd" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_create_order_response())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, _} =
               ExCoinbase.limit_order_gtd(
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
    test "delegates to Orders.limit_order_fok" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_create_order_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, _} = ExCoinbase.limit_order_fok(client, "BTC-USD", "BUY", "0.001", "50000")
    end
  end

  describe "stop_limit_order_gtd/7" do
    test "delegates to Orders.stop_limit_order_gtd" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_create_order_response())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, _} =
               ExCoinbase.stop_limit_order_gtd(
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
    test "delegates to Orders.edit_order" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_edit_order_response())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, %{"success" => true}} =
               ExCoinbase.edit_order(client, "order-123", price: "51000")
    end
  end

  describe "edit_order_preview/3" do
    test "delegates to Orders.edit_order_preview" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_edit_order_preview_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, _} = ExCoinbase.edit_order_preview(client, "order-123", price: "51000")
    end
  end

  describe "preview_order/2" do
    test "delegates to Orders.preview_order" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_preview_order_response())
      end)

      client = Fixtures.test_client(@stub_name)

      params = %{
        product_id: "BTC-USD",
        side: "BUY",
        order_configuration: %{market_market_ioc: %{quote_size: "100"}}
      }

      assert {:ok, _} = ExCoinbase.preview_order(client, params)
    end
  end

  describe "close_position/4" do
    test "delegates to Orders.close_position" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_close_position_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, _} = ExCoinbase.close_position(client, "close-123", "BTC-USD")
    end
  end

  describe "cancel_orders/2" do
    test "delegates to Orders.cancel_orders" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_cancel_orders_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"results" => _}} = ExCoinbase.cancel_orders(client, ["order-1"])
    end
  end

  describe "cancel_order/2" do
    test "delegates to Orders.cancel_order" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, %{"results" => [%{"success" => true, "order_id" => "order-1"}]})
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, _} = ExCoinbase.cancel_order(client, "order-1")
    end
  end

  describe "list_orders/2" do
    test "delegates to Orders.list_orders" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_orders_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"orders" => _}} = ExCoinbase.list_orders(client)
    end
  end

  describe "get_order/2" do
    test "delegates to Orders.get_order" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_single_order_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"order" => _}} = ExCoinbase.get_order(client, "order-1")
    end
  end

  describe "list_fills/2" do
    test "delegates to Orders.list_fills" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_fills_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"fills" => _}} = ExCoinbase.list_fills(client)
    end
  end

  describe "extract_orders/1" do
    test "delegates to Orders.extract_orders" do
      response = Fixtures.sample_orders_response()
      assert length(ExCoinbase.extract_orders(response)) == 2
    end
  end

  describe "extract_fills/1" do
    test "delegates to Orders.extract_fills" do
      response = Fixtures.sample_fills_response()
      assert length(ExCoinbase.extract_fills(response)) == 1
    end
  end

  describe "validate_order_params/1" do
    test "delegates to Orders.validate_order_params" do
      params = %{
        product_id: "BTC-USD",
        side: "BUY",
        order_configuration: %{market_market_ioc: %{quote_size: "100"}}
      }

      assert {:ok, ^params} = ExCoinbase.validate_order_params(params)
    end
  end

  describe "valid_sides/0" do
    test "delegates to Orders.valid_sides" do
      sides = ExCoinbase.valid_sides()
      assert "BUY" in sides
      assert "SELL" in sides
    end
  end

  describe "valid_order_types/0" do
    test "delegates to Orders.valid_order_types" do
      types = ExCoinbase.valid_order_types()
      assert is_list(types)
      assert types != []
    end
  end

  describe "valid_time_in_force/0" do
    test "delegates to Orders.valid_time_in_force" do
      tif = ExCoinbase.valid_time_in_force()
      assert is_list(tif)
      assert tif != []
    end
  end

  # ============================================================================
  # Portfolio delegates
  # ============================================================================

  describe "list_portfolios/2" do
    test "delegates to Portfolio.list_portfolios" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_portfolios_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"portfolios" => _}} = ExCoinbase.list_portfolios(client)
    end
  end

  describe "create_portfolio/2" do
    test "delegates to Portfolio.create_portfolio" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_portfolio_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"portfolio" => _}} = ExCoinbase.create_portfolio(client, "My Portfolio")
    end
  end

  describe "get_portfolio_breakdown/2" do
    test "delegates to Portfolio.get_portfolio_breakdown" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_portfolio_breakdown_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"breakdown" => _}} = ExCoinbase.get_portfolio_breakdown(client, "uuid")
    end
  end

  describe "move_funds/2" do
    test "delegates to Portfolio.move_funds" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_move_funds_response())
      end)

      client = Fixtures.test_client(@stub_name)

      params = %{
        source_portfolio_uuid: "source-uuid",
        target_portfolio_uuid: "target-uuid",
        funds: %{value: "100.00", currency: "USD"}
      }

      assert {:ok, _} = ExCoinbase.move_funds(client, params)
    end
  end

  describe "delete_portfolio/2" do
    test "delegates to Portfolio.delete_portfolio" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, %{})
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, _} = ExCoinbase.delete_portfolio(client, "uuid")
    end
  end

  describe "edit_portfolio/3" do
    test "delegates to Portfolio.edit_portfolio" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, %{"portfolio" => %{"uuid" => "uuid", "name" => "New Name"}})
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"portfolio" => _}} = ExCoinbase.edit_portfolio(client, "uuid", "New Name")
    end
  end

  describe "extract_portfolios/1" do
    test "delegates to Portfolio.extract_portfolios" do
      response = Fixtures.sample_portfolios_response()
      assert length(ExCoinbase.extract_portfolios(response)) == 2
    end
  end

  describe "extract_spot_positions/1" do
    test "delegates to Portfolio.extract_spot_positions" do
      breakdown = Fixtures.sample_portfolio_breakdown_response()
      positions = ExCoinbase.extract_spot_positions(breakdown)
      assert length(positions) == 1
    end
  end

  # ============================================================================
  # Fee delegates
  # ============================================================================

  describe "get_transaction_summary/2" do
    test "delegates to Fees.get_transaction_summary" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_transaction_summary_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"fee_tier" => _}} = ExCoinbase.get_transaction_summary(client)
    end
  end

  describe "maker_fee_rate/1" do
    test "delegates to Fees.maker_fee_rate" do
      summary = Fixtures.sample_transaction_summary_response()
      rate = ExCoinbase.maker_fee_rate(summary)
      assert Decimal.equal?(rate, Decimal.new("0.004"))
    end
  end

  describe "taker_fee_rate/1" do
    test "delegates to Fees.taker_fee_rate" do
      summary = Fixtures.sample_transaction_summary_response()
      rate = ExCoinbase.taker_fee_rate(summary)
      assert Decimal.equal?(rate, Decimal.new("0.006"))
    end
  end

  describe "estimate_fee/3" do
    test "delegates to Fees.estimate_fee" do
      summary = Fixtures.sample_transaction_summary_response()
      fee = ExCoinbase.estimate_fee(summary, Decimal.new("1000"), true)
      assert Decimal.equal?(fee, Decimal.new("4.000"))
    end
  end

  # ============================================================================
  # Client delegates (verify_credentials and healthcheck)
  # ============================================================================

  describe "verify_credentials/3" do
    test "delegates to Client.verify_credentials" do
      assert {:error, {:invalid_private_key, _}} =
               ExCoinbase.verify_credentials(Fixtures.sample_api_key(), Fixtures.invalid_pem())
    end
  end

  describe "healthcheck/1" do
    test "delegates to Client.healthcheck" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, %{"accounts" => []})
      end)

      client = Fixtures.test_client(@stub_name)
      assert :ok = ExCoinbase.healthcheck(client)
    end
  end

  # ============================================================================
  # 0.2.0 delegates
  # ============================================================================

  describe "0.2.0 facade delegates" do
    defp routed_client do
      Req.Test.stub(@stub_name, fn conn ->
        body =
          case conn.request_path do
            "/api/v3/brokerage/products" ->
              %{"products" => [%{"product_id" => "PM", "product_type" => "PREDICTION_MARKETS"}]}

            "/api/v3/brokerage/portfolios/pf" ->
              %{"breakdown" => %{"prediction_markets_positions" => [%{"cbrn" => "1"}]}}

            "/api/v3/brokerage/orders/historical/batch" ->
              %{"orders" => [%{"order_id" => "1", "prediction_side" => "PREDICTION_SIDE_NO"}]}

            "/api/v3/brokerage/orders/preview" ->
              %{"prediction_order_metadata" => %{"minimum_contracts" => "2"}}

            path ->
              %{"path" => path, "method" => conn.method, "query" => conn.query_string}
          end

        Req.Test.json(conn, body)
      end)

      Fixtures.test_client(@stub_name)
    end

    defp public_client do
      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, %{"path" => conn.request_path, "query" => conn.query_string})
      end)

      ExCoinbase.public(plug: {Req.Test, @stub_name}) |> Req.Request.merge_options(retry: false)
    end

    test "client and key permissions" do
      client = routed_client()

      assert {:ok, %{"path" => "/api/v3/brokerage/key_permissions"}} =
               ExCoinbase.key_permissions(client)

      assert %Req.Request{} = ExCoinbase.public()
    end

    test "new order helpers" do
      client = routed_client()

      assert {:ok, %{"path" => "/api/v3/brokerage/orders"}} =
               ExCoinbase.market_order_fok(client, "BTC-PERP-INTX", "BUY", "1")

      assert {:ok, %{"path" => "/api/v3/brokerage/orders"}} =
               ExCoinbase.twap_order_gtd(client, "BTC-USD", "BUY", %{base_size: "1"}, "1",
                 start_time: "a",
                 end_time: "b",
                 number_buckets: "1",
                 bucket_size: "1",
                 bucket_duration: "1s"
               )

      assert {:ok, %{"path" => "/api/v3/brokerage/orders"}} =
               ExCoinbase.scaled_order_gtc(client, "BTC-USD", "BUY", %{quote_size: "1"},
                 num_orders: "2",
                 min_price: "1",
                 max_price: "2"
               )

      assert ExCoinbase.valid_prediction_sides() == ["PREDICTION_SIDE_YES", "PREDICTION_SIDE_NO"]
    end

    test "prediction markets" do
      client = routed_client()
      orders = "/api/v3/brokerage/orders"
      assert {:ok, %{"path" => ^orders}} = ExCoinbase.buy_yes(client, "PM", "1")
      assert {:ok, %{"path" => ^orders}} = ExCoinbase.buy_no(client, "PM", "1")
      assert {:ok, %{"path" => ^orders}} = ExCoinbase.sell_yes(client, "PM", "1")
      assert {:ok, %{"path" => ^orders}} = ExCoinbase.sell_no(client, "PM", "1")
      assert {:ok, preview} = ExCoinbase.preview_yes(client, "PM", "1")
      assert {:ok, _} = ExCoinbase.preview_no(client, "PM", "1")
      assert ExCoinbase.extract_prediction_metadata(preview)["minimum_contracts"] == "2"
      assert {:ok, [%{"product_id" => "PM"}]} = ExCoinbase.list_markets(client)

      assert {:ok, %{"path" => "/api/v3/brokerage/products/PM"}} =
               ExCoinbase.get_market(client, "PM")

      assert {:ok, [%{"cbrn" => "1"}]} = ExCoinbase.list_prediction_positions(client, "pf")
      assert {:ok, [%{"order_id" => "1"}]} = ExCoinbase.list_prediction_orders(client)

      assert ExCoinbase.extract_prediction_positions(%{"prediction_markets_positions" => [1]}) ==
               [1]

      assert [%{"type" => "ACCOUNT_TYPE_PREDICTION_MARKETS_CFM"}] =
               ExCoinbase.prediction_accounts([
                 %{"type" => "ACCOUNT_TYPE_CRYPTO"},
                 %{"type" => "ACCOUNT_TYPE_PREDICTION_MARKETS_CFM"}
               ])
    end

    test "public market data" do
      client = public_client()
      assert {:ok, %{"path" => "/api/v3/brokerage/time"}} = ExCoinbase.server_time(client)

      assert {:ok, %{"path" => "/api/v3/brokerage/market/products"}} =
               ExCoinbase.public_list_products(client)

      assert {:ok, %{"path" => "/api/v3/brokerage/market/products/BTC-USD"}} =
               ExCoinbase.public_get_product(client, "BTC-USD")

      assert {:ok, %{"path" => "/api/v3/brokerage/market/products/BTC-USD/candles"}} =
               ExCoinbase.public_get_candles(client, "BTC-USD",
                 start: "1",
                 end: "2",
                 granularity: "ONE_HOUR"
               )

      assert {:ok, %{"path" => "/api/v3/brokerage/market/products/BTC-USD/ticker"}} =
               ExCoinbase.public_get_market_trades(client, "BTC-USD")

      assert {:ok,
              %{
                "path" => "/api/v3/brokerage/market/product_book",
                "query" => "product_id=BTC-USD"
              }} =
               ExCoinbase.public_get_product_book(client, "BTC-USD")
    end

    test "convert and payment methods" do
      client = routed_client()

      assert {:ok, %{"path" => "/api/v3/brokerage/convert/quote", "method" => "POST"}} =
               ExCoinbase.create_convert_quote(client, "a", "b", "1")

      assert {:ok, %{"path" => "/api/v3/brokerage/convert/trade/t1", "method" => "GET"}} =
               ExCoinbase.get_convert_trade(client, "t1", "a", "b")

      assert {:ok, %{"path" => "/api/v3/brokerage/convert/trade/t1", "method" => "POST"}} =
               ExCoinbase.commit_convert_trade(client, "t1", "a", "b")

      assert {:ok, %{"path" => "/api/v3/brokerage/payment_methods"}} =
               ExCoinbase.list_payment_methods(client)

      assert {:ok, %{"path" => "/api/v3/brokerage/payment_methods/pm1"}} =
               ExCoinbase.get_payment_method(client, "pm1")
    end

    test "US futures" do
      client = routed_client()
      cfm = "/api/v3/brokerage/cfm"

      assert {:ok, %{"path" => "/api/v3/brokerage/cfm/balance_summary"}} =
               ExCoinbase.futures_balance_summary(client)

      assert {:ok, %{"path" => "/api/v3/brokerage/cfm/positions"}} =
               ExCoinbase.list_futures_positions(client)

      assert {:ok, %{"path" => "/api/v3/brokerage/cfm/positions/BIT-27FEB26-CDE"}} =
               ExCoinbase.get_futures_position(client, "BIT-27FEB26-CDE")

      assert {:ok, %{"path" => "/api/v3/brokerage/cfm/sweeps/schedule", "method" => "POST"}} =
               ExCoinbase.schedule_futures_sweep(client, "10")

      assert {:ok, %{"path" => "/api/v3/brokerage/cfm/sweeps", "method" => "GET"}} =
               ExCoinbase.list_futures_sweeps(client)

      assert {:ok, %{"path" => "/api/v3/brokerage/cfm/sweeps", "method" => "DELETE"}} =
               ExCoinbase.cancel_futures_sweep(client)

      assert {:ok, %{"path" => path}} = ExCoinbase.get_intraday_margin_setting(client)
      assert path == cfm <> "/intraday/margin_setting"

      assert {:ok, %{"method" => "POST"}} =
               ExCoinbase.set_intraday_margin_setting(client, "INTRADAY_MARGIN_SETTING_STANDARD")

      assert {:ok, %{"query" => "margin_profile_type=X"}} =
               ExCoinbase.current_margin_window(client, margin_profile_type: "X")
    end
  end
end
