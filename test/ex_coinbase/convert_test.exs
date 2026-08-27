defmodule ExCoinbase.ConvertTest do
  use ExUnit.Case, async: true

  alias ExCoinbase.Convert
  alias ExCoinbase.Fixtures
  alias ExCoinbase.RestFixtures

  @stub_name ExCoinbase.ConvertTest

  defp client, do: Fixtures.test_client(@stub_name)

  defp read_json_body(conn) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    {Jason.decode!(body), conn}
  end

  describe "create_quote/5" do
    test "posts from_account, to_account and amount to /convert/quote" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/api/v3/brokerage/convert/quote"
        {body, conn} = read_json_body(conn)

        assert body == %{
                 "from_account" => "usd-acct",
                 "to_account" => "usdc-acct",
                 "amount" => "100.00"
               }

        Req.Test.json(conn, RestFixtures.convert_trade_response())
      end)

      assert {:ok, %{"trade" => %{"id" => "trade-id-123"}}} =
               Convert.create_quote(client(), "usd-acct", "usdc-acct", "100.00")
    end

    test "includes trade_incentive_metadata when given" do
      Req.Test.expect(@stub_name, fn conn ->
        {body, conn} = read_json_body(conn)

        assert body["trade_incentive_metadata"] == %{
                 "user_incentive_id" => "inc-1",
                 "code_val" => "PROMO"
               }

        Req.Test.json(conn, RestFixtures.convert_trade_response())
      end)

      assert {:ok, _} =
               Convert.create_quote(client(), "usd-acct", "usdc-acct", "100.00",
                 trade_incentive_metadata: %{user_incentive_id: "inc-1", code_val: "PROMO"}
               )
    end

    test "returns error on unauthorized" do
      Req.Test.expect(@stub_name, fn conn ->
        conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"error" => "Unauthorized"})
      end)

      assert {:error, :unauthorized} = Convert.create_quote(client(), "a", "b", "1")
    end
  end

  describe "get_trade/4" do
    test "gets /convert/trade/{id} with account query params" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api/v3/brokerage/convert/trade/trade-id-123"
        assert conn.query_string == "from_account=usd-acct&to_account=usdc-acct"
        Req.Test.json(conn, RestFixtures.convert_trade_response())
      end)

      assert {:ok, %{"trade" => %{"id" => "trade-id-123"}}} =
               Convert.get_trade(client(), "trade-id-123", "usd-acct", "usdc-acct")
    end

    test "returns not_found for unknown trade" do
      Req.Test.expect(@stub_name, fn conn ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"error" => "not found"})
      end)

      assert {:error, :not_found} = Convert.get_trade(client(), "nope", "a", "b")
    end
  end

  describe "commit_trade/4" do
    test "posts accounts to /convert/trade/{id}" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/api/v3/brokerage/convert/trade/trade-id-123"
        {body, conn} = read_json_body(conn)
        assert body == %{"from_account" => "usd-acct", "to_account" => "usdc-acct"}
        Req.Test.json(conn, RestFixtures.convert_trade_response("TRADE_STATUS_COMPLETED"))
      end)

      assert {:ok, %{"trade" => %{"status" => "TRADE_STATUS_COMPLETED"}}} =
               Convert.commit_trade(client(), "trade-id-123", "usd-acct", "usdc-acct")
    end
  end
end
