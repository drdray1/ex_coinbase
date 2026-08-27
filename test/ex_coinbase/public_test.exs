defmodule ExCoinbase.PublicTest do
  use ExUnit.Case, async: true

  alias ExCoinbase.Public
  alias ExCoinbase.RestFixtures

  @stub_name ExCoinbase.PublicTest

  defp client, do: RestFixtures.public_client(@stub_name)

  # ============================================================================
  # HTTP Endpoint Tests
  # ============================================================================

  describe "server_time/1" do
    test "fetches /time" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api/v3/brokerage/time"
        refute Enum.any?(conn.req_headers, fn {k, _} -> k == "authorization" end)
        Req.Test.json(conn, RestFixtures.server_time_response())
      end)

      assert {:ok, %{"iso" => "2024-01-01T00:00:00Z"}} = Public.server_time(client())
    end
  end

  describe "list_products/2" do
    test "fetches /market/products with no query by default" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api/v3/brokerage/market/products"
        assert conn.query_string == ""
        Req.Test.json(conn, RestFixtures.public_products_response())
      end)

      assert {:ok, %{"products" => products}} = Public.list_products(client())
      assert length(products) == 2
    end

    test "encodes allowed options including repeated product_ids" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.query_string ==
                 "limit=10&product_ids=BTC-USD&product_ids=ETH-USD&product_type=SPOT&get_all_products=true"

        Req.Test.json(conn, RestFixtures.public_products_response())
      end)

      assert {:ok, _} =
               Public.list_products(client(),
                 limit: 10,
                 product_ids: ["BTC-USD", "ETH-USD"],
                 product_type: "SPOT",
                 get_all_products: true,
                 bogus: "ignored"
               )
    end

    test "returns error on server failure" do
      Req.Test.expect(@stub_name, fn conn ->
        conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"error" => "boom"})
      end)

      assert {:error, _} = Public.list_products(client())
    end
  end

  describe "get_product/2" do
    test "fetches /market/products/{id}" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api/v3/brokerage/market/products/BTC-USD"
        Req.Test.json(conn, RestFixtures.public_product_response())
      end)

      assert {:ok, %{"product_id" => "BTC-USD"}} = Public.get_product(client(), "BTC-USD")
    end

    test "returns not_found for unknown product" do
      Req.Test.expect(@stub_name, fn conn ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"error" => "not found"})
      end)

      assert {:error, :not_found} = Public.get_product(client(), "NOPE-USD")
    end
  end

  describe "get_candles/3" do
    test "fetches candles with required params" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api/v3/brokerage/market/products/BTC-USD/candles"
        assert conn.query_string == "start=1700000000&end=1700086400&granularity=ONE_HOUR"
        Req.Test.json(conn, RestFixtures.candles_response())
      end)

      assert {:ok, %{"candles" => [_]}} =
               Public.get_candles(client(), "BTC-USD",
                 start: "1700000000",
                 end: "1700086400",
                 granularity: "ONE_HOUR"
               )
    end

    test "includes optional limit" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.query_string == "start=1&end=2&granularity=ONE_DAY&limit=5"
        Req.Test.json(conn, RestFixtures.candles_response())
      end)

      assert {:ok, _} =
               Public.get_candles(client(), "BTC-USD",
                 start: "1",
                 end: "2",
                 granularity: "ONE_DAY",
                 limit: 5
               )
    end

    test "requires start, end and granularity" do
      assert {:error, "start is required"} =
               Public.get_candles(client(), "BTC-USD", end: "2", granularity: "ONE_DAY")

      assert {:error, "end is required"} =
               Public.get_candles(client(), "BTC-USD", start: "1", granularity: "ONE_DAY")

      assert {:error, "granularity is required"} =
               Public.get_candles(client(), "BTC-USD", start: "1", end: "2")
    end

    test "rejects invalid granularity" do
      assert {:error, "granularity must be one of: " <> list} =
               Public.get_candles(client(), "BTC-USD", start: "1", end: "2", granularity: "BOGUS")

      assert list == Enum.join(ExCoinbase.Products.valid_granularities(), ", ")
    end
  end

  describe "get_market_trades/3" do
    test "fetches /market/products/{id}/ticker" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api/v3/brokerage/market/products/BTC-USD/ticker"
        assert conn.query_string == "limit=10&start=1&end=2"
        Req.Test.json(conn, RestFixtures.market_trades_response())
      end)

      assert {:ok, %{"trades" => [_], "best_bid" => _}} =
               Public.get_market_trades(client(), "BTC-USD", limit: 10, start: "1", end: "2")
    end

    test "works with no options" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.query_string == ""
        Req.Test.json(conn, RestFixtures.market_trades_response())
      end)

      assert {:ok, _} = Public.get_market_trades(client(), "BTC-USD")
    end
  end

  describe "get_product_book/3" do
    test "fetches /market/product_book with product_id query" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api/v3/brokerage/market/product_book"
        assert conn.query_string == "product_id=BTC-USD"
        Req.Test.json(conn, RestFixtures.product_book_response())
      end)

      assert {:ok, %{"pricebook" => %{"bids" => [_]}}} =
               Public.get_product_book(client(), "BTC-USD")
    end

    test "includes limit and aggregation_price_increment" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.query_string == "product_id=BTC-USD&limit=5&aggregation_price_increment=0.01"
        Req.Test.json(conn, RestFixtures.product_book_response())
      end)

      assert {:ok, _} =
               Public.get_product_book(client(), "BTC-USD",
                 limit: 5,
                 aggregation_price_increment: "0.01"
               )
    end
  end
end
