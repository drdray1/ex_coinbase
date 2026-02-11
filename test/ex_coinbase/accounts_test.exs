defmodule ExCoinbase.AccountsTest do
  use ExUnit.Case, async: true

  alias ExCoinbase.Accounts
  alias ExCoinbase.Fixtures

  @stub_name ExCoinbase.AccountsTest

  # ============================================================================
  # HTTP Endpoint Tests
  # ============================================================================

  describe "list_accounts/2" do
    test "returns accounts on successful request" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_accounts_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"accounts" => accounts}} = Accounts.list_accounts(client)
      assert length(accounts) == 2
    end

    test "returns error for unauthorized request" do
      Req.Test.expect(@stub_name, fn conn ->
        conn
        |> Plug.Conn.put_status(401)
        |> Req.Test.json(%{"error" => "Unauthorized"})
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:error, :unauthorized} = Accounts.list_accounts(client)
    end

    test "returns error for rate limiting" do
      Req.Test.expect(@stub_name, fn conn ->
        conn
        |> Plug.Conn.put_status(429)
        |> Req.Test.json(%{"error" => "Rate limited"})
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:error, :rate_limited} = Accounts.list_accounts(client)
    end
  end

  describe "get_account/2" do
    test "returns account on success" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_account_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"account" => account}} = Accounts.get_account(client, "test-account-uuid")
      assert account["uuid"] == "test-account-uuid"
    end

    test "returns error for not found" do
      Req.Test.expect(@stub_name, fn conn ->
        conn
        |> Plug.Conn.put_status(404)
        |> Req.Test.json(%{"error" => "Not found"})
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:error, :not_found} = Accounts.get_account(client, "nonexistent-uuid")
    end
  end

  # ============================================================================
  # Pure Function Tests
  # ============================================================================

  describe "extract_accounts/1" do
    test "extracts accounts from valid response" do
      response = %{
        "accounts" => [
          %{"uuid" => "acc-1", "currency" => "BTC"},
          %{"uuid" => "acc-2", "currency" => "USD"}
        ]
      }

      accounts = Accounts.extract_accounts(response)

      assert length(accounts) == 2
      assert Enum.at(accounts, 0)["uuid"] == "acc-1"
    end

    test "returns empty list for missing accounts" do
      assert Accounts.extract_accounts(%{}) == []
      assert Accounts.extract_accounts(nil) == []
    end
  end

  describe "extract_account/1" do
    test "extracts single account from response" do
      response = %{
        "account" => %{"uuid" => "acc-1", "currency" => "BTC"}
      }

      account = Accounts.extract_account(response)

      assert account["uuid"] == "acc-1"
      assert account["currency"] == "BTC"
    end

    test "returns nil for missing account" do
      assert Accounts.extract_account(%{}) == nil
      assert Accounts.extract_account(nil) == nil
    end
  end

  describe "find_by_currency/2" do
    test "finds account by currency" do
      accounts = [
        %{"uuid" => "acc-1", "currency" => "BTC"},
        %{"uuid" => "acc-2", "currency" => "USD"},
        %{"uuid" => "acc-3", "currency" => "ETH"}
      ]

      assert Accounts.find_by_currency(accounts, "USD")["uuid"] == "acc-2"
      assert Accounts.find_by_currency(accounts, "ETH")["uuid"] == "acc-3"
    end

    test "returns nil when currency not found" do
      accounts = [%{"uuid" => "acc-1", "currency" => "BTC"}]
      assert Accounts.find_by_currency(accounts, "DOGE") == nil
    end

    test "returns nil for empty list" do
      assert Accounts.find_by_currency([], "BTC") == nil
    end
  end

  describe "total_available/2" do
    test "sums available balances for currency" do
      accounts = [
        %{
          "uuid" => "acc-1",
          "currency" => "USD",
          "available_balance" => %{"value" => "1000.00"}
        },
        %{
          "uuid" => "acc-2",
          "currency" => "USD",
          "available_balance" => %{"value" => "500.50"}
        },
        %{
          "uuid" => "acc-3",
          "currency" => "BTC",
          "available_balance" => %{"value" => "1.5"}
        }
      ]

      total = Accounts.total_available(accounts, "USD")
      assert Decimal.equal?(total, Decimal.new("1500.50"))
    end

    test "returns zero for non-existent currency" do
      accounts = [
        %{"uuid" => "acc-1", "currency" => "BTC", "available_balance" => %{"value" => "1.0"}}
      ]

      total = Accounts.total_available(accounts, "DOGE")
      assert Decimal.equal?(total, Decimal.new("0"))
    end
  end
end
