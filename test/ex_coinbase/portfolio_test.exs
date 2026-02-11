defmodule ExCoinbase.PortfolioTest do
  use ExUnit.Case, async: true

  alias ExCoinbase.Portfolio
  alias ExCoinbase.Fixtures

  describe "extract_portfolios/1" do
    test "extracts portfolios from valid response" do
      response = Fixtures.sample_portfolios_response()
      portfolios = Portfolio.extract_portfolios(response)
      assert length(portfolios) == 2
    end

    test "returns empty list for missing portfolios" do
      assert Portfolio.extract_portfolios(%{}) == []
      assert Portfolio.extract_portfolios(nil) == []
    end
  end

  describe "find_default/1" do
    test "finds the default portfolio" do
      response = Fixtures.sample_portfolios_response()
      portfolios = Portfolio.extract_portfolios(response)
      default = Portfolio.find_default(portfolios)
      assert default["type"] == "DEFAULT"
      assert default["name"] == "Default"
    end

    test "returns nil when no default" do
      portfolios = [%{"uuid" => "1", "type" => "CONSUMER"}]
      assert Portfolio.find_default(portfolios) == nil
    end
  end

  describe "find_by_name/2" do
    test "finds portfolio by name" do
      response = Fixtures.sample_portfolios_response()
      portfolios = Portfolio.extract_portfolios(response)
      found = Portfolio.find_by_name(portfolios, "Trading Portfolio")
      assert found["uuid"] == "trading-portfolio-uuid"
    end

    test "returns nil when name not found" do
      portfolios = [%{"name" => "Default"}]
      assert Portfolio.find_by_name(portfolios, "Not Found") == nil
    end
  end

  describe "extract_spot_positions/1" do
    test "extracts positions from breakdown" do
      breakdown = Fixtures.sample_portfolio_breakdown_response()
      positions = Portfolio.extract_spot_positions(breakdown)
      assert length(positions) == 1
      assert Enum.at(positions, 0)["asset"] == "BTC"
    end

    test "returns empty list for missing positions" do
      assert Portfolio.extract_spot_positions(%{}) == []
    end
  end

  describe "total_value/1" do
    test "extracts total value from breakdown" do
      breakdown = %{
        "portfolio_balances" => %{
          "total_balance" => %{"value" => "15000.00", "currency" => "USD"}
        }
      }

      value = Portfolio.total_value(breakdown)
      assert Decimal.equal?(value, Decimal.new("15000.00"))
    end

    test "returns zero for missing balance" do
      value = Portfolio.total_value(%{})
      assert Decimal.equal?(value, Decimal.new("0"))
    end
  end

  describe "valid_portfolio_types/0" do
    test "includes expected types" do
      types = Portfolio.valid_portfolio_types()
      assert "DEFAULT" in types
      assert "CONSUMER" in types
    end
  end
end
