defmodule ExCoinbaseTest do
  use ExUnit.Case, async: true

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
end
