defmodule ExCoinbase.PortfolioTest do
  use ExUnit.Case, async: true

  alias ExCoinbase.Portfolio
  alias ExCoinbase.Fixtures

  @stub_name ExCoinbase.PortfolioTest

  # ============================================================================
  # HTTP Endpoint Tests
  # ============================================================================

  describe "list_portfolios/2" do
    test "returns portfolios on success" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_portfolios_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"portfolios" => portfolios}} = Portfolio.list_portfolios(client)
      assert length(portfolios) == 2
    end
  end

  describe "create_portfolio/2" do
    test "returns created portfolio" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_portfolio_response())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, %{"portfolio" => portfolio}} =
               Portfolio.create_portfolio(client, "Trading Portfolio")

      assert portfolio["name"] == "Trading Portfolio"
    end
  end

  describe "get_portfolio_breakdown/2" do
    test "returns breakdown on success" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_portfolio_breakdown_response())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, %{"breakdown" => breakdown}} =
               Portfolio.get_portfolio_breakdown(client, "portfolio-uuid")

      assert breakdown["portfolio"]["uuid"] == "portfolio-uuid"
    end
  end

  describe "move_funds/2" do
    test "returns success for valid params" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_move_funds_response())
      end)

      client = Fixtures.test_client(@stub_name)

      params = %{
        source_portfolio_uuid: "source-uuid",
        target_portfolio_uuid: "target-uuid",
        funds: %{value: "100.00", currency: "USD"}
      }

      assert {:ok, _} = Portfolio.move_funds(client, params)
    end

    test "returns validation error for missing source_portfolio_uuid" do
      client = Fixtures.test_client(@stub_name)

      params = %{
        target_portfolio_uuid: "target-uuid",
        funds: %{value: "100.00", currency: "USD"}
      }

      assert {:error, {:validation_error, errors}} = Portfolio.move_funds(client, params)
      assert "source_portfolio_uuid is required" in errors
    end

    test "returns validation error for missing funds" do
      client = Fixtures.test_client(@stub_name)

      params = %{
        source_portfolio_uuid: "source-uuid",
        target_portfolio_uuid: "target-uuid"
      }

      assert {:error, {:validation_error, errors}} = Portfolio.move_funds(client, params)
      assert "funds is required" in errors
    end
  end

  describe "delete_portfolio/2" do
    test "returns success" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, %{})
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, _} = Portfolio.delete_portfolio(client, "portfolio-uuid")
    end
  end

  describe "edit_portfolio/3" do
    test "returns updated portfolio" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, %{"portfolio" => %{"uuid" => "portfolio-uuid", "name" => "New Name"}})
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, %{"portfolio" => portfolio}} =
               Portfolio.edit_portfolio(client, "portfolio-uuid", "New Name")

      assert portfolio["name"] == "New Name"
    end
  end

  # ============================================================================
  # Extractor Tests
  # ============================================================================

  describe "extract_portfolio/1" do
    test "extracts single portfolio" do
      response = Fixtures.sample_portfolio_response()
      portfolio = Portfolio.extract_portfolio(response)
      assert portfolio["uuid"] == "portfolio-uuid"
    end

    test "returns nil for missing portfolio" do
      assert Portfolio.extract_portfolio(%{}) == nil
    end
  end

  describe "extract_breakdown/1" do
    test "extracts breakdown from response" do
      response = Fixtures.sample_portfolio_breakdown_response()
      breakdown = Portfolio.extract_breakdown(response)
      assert breakdown["portfolio"]["uuid"] == "portfolio-uuid"
    end

    test "returns nil for missing breakdown" do
      assert Portfolio.extract_breakdown(%{}) == nil
    end
  end

  # ============================================================================
  # Pure Function Tests
  # ============================================================================

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
