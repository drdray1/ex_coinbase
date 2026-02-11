defmodule ExCoinbase.ProductsTest do
  use ExUnit.Case, async: true

  alias ExCoinbase.Fixtures
  alias ExCoinbase.Products

  @stub_name ExCoinbase.ProductsTest

  # ============================================================================
  # HTTP Endpoint Tests
  # ============================================================================

  describe "list_products/2" do
    test "returns products on success" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_products_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"products" => products}} = Products.list_products(client)
      assert length(products) == 2
    end

    test "returns error on failure" do
      Req.Test.expect(@stub_name, fn conn ->
        conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"error" => "Unauthorized"})
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:error, :unauthorized} = Products.list_products(client)
    end
  end

  describe "get_product/2" do
    test "returns product on success" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, %{"product_id" => "BTC-USD", "price" => "50000.00"})
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"product_id" => "BTC-USD"}} = Products.get_product(client, "BTC-USD")
    end
  end

  describe "get_candles/3" do
    test "returns candles on success with valid params" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_candles_response())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, %{"candles" => candles}} =
               Products.get_candles(client, "BTC-USD",
                 start: "1704067200",
                 end: "1704070800",
                 granularity: "ONE_HOUR"
               )

      assert length(candles) == 2
    end

    test "returns error when start is missing" do
      client = Fixtures.test_client(@stub_name)

      assert {:error, "start is required"} =
               Products.get_candles(client, "BTC-USD", end: "1", granularity: "ONE_HOUR")
    end

    test "returns error when end is missing" do
      client = Fixtures.test_client(@stub_name)

      assert {:error, "end is required"} =
               Products.get_candles(client, "BTC-USD", start: "1", granularity: "ONE_HOUR")
    end

    test "returns error when granularity is missing" do
      client = Fixtures.test_client(@stub_name)

      assert {:error, "granularity is required"} =
               Products.get_candles(client, "BTC-USD", start: "1", end: "2")
    end

    test "returns error for invalid granularity" do
      client = Fixtures.test_client(@stub_name)

      assert {:error, msg} =
               Products.get_candles(client, "BTC-USD",
                 start: "1",
                 end: "2",
                 granularity: "INVALID"
               )

      assert String.contains?(msg, "granularity must be one of")
    end
  end

  describe "get_market_trades/3" do
    test "returns trades on success" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_market_trades_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"trades" => trades}} = Products.get_market_trades(client, "BTC-USD")
      assert length(trades) == 1
    end
  end

  describe "get_best_bid_ask/2" do
    test "returns pricebooks on success" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_best_bid_ask_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"pricebooks" => pricebooks}} = Products.get_best_bid_ask(client, ["BTC-USD"])
      assert length(pricebooks) == 1
    end
  end

  describe "get_product_book/3" do
    test "returns order book on success" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_product_book_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"pricebook" => pricebook}} = Products.get_product_book(client, "BTC-USD")
      assert pricebook["product_id"] == "BTC-USD"
    end
  end

  # ============================================================================
  # Pure Function Tests
  # ============================================================================

  describe "extract_products/1" do
    test "extracts products from valid response" do
      response = Fixtures.sample_products_response()
      products = Products.extract_products(response)
      assert length(products) == 2
      assert Enum.at(products, 0)["product_id"] == "BTC-USD"
    end

    test "returns empty list for missing products" do
      assert Products.extract_products(%{}) == []
      assert Products.extract_products(nil) == []
    end
  end

  describe "extract_candles/1" do
    test "extracts candles from valid response" do
      response = Fixtures.sample_candles_response()
      candles = Products.extract_candles(response)
      assert length(candles) == 2
    end

    test "returns empty list for missing candles" do
      assert Products.extract_candles(%{}) == []
    end
  end

  describe "valid_granularities/0" do
    test "includes expected granularities" do
      granularities = Products.valid_granularities()
      assert "ONE_MINUTE" in granularities
      assert "ONE_HOUR" in granularities
      assert "ONE_DAY" in granularities
    end
  end

  describe "filter_by_quote_currency/2" do
    test "filters products by quote currency" do
      products = [
        %{"product_id" => "BTC-USD", "quote_currency_id" => "USD"},
        %{"product_id" => "BTC-EUR", "quote_currency_id" => "EUR"},
        %{"product_id" => "ETH-USD", "quote_currency_id" => "USD"}
      ]

      usd_products = Products.filter_by_quote_currency(products, "USD")
      assert length(usd_products) == 2
    end
  end

  describe "filter_by_base_currency/2" do
    test "filters products by base currency" do
      products = [
        %{"product_id" => "BTC-USD", "base_currency_id" => "BTC"},
        %{"product_id" => "ETH-USD", "base_currency_id" => "ETH"},
        %{"product_id" => "BTC-EUR", "base_currency_id" => "BTC"}
      ]

      btc_products = Products.filter_by_base_currency(products, "BTC")
      assert length(btc_products) == 2
    end
  end
end
