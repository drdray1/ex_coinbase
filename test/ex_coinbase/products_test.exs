defmodule ExCoinbase.ProductsTest do
  use ExUnit.Case, async: true

  alias ExCoinbase.Products
  alias ExCoinbase.Fixtures

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
