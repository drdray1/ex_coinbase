defmodule ExCoinbase.PerpetualsTest do
  use ExUnit.Case, async: true

  alias ExCoinbase.Perpetuals
  alias ExCoinbase.RestFixtures

  @stub_name ExCoinbase.PerpetualsTest

  defp client, do: RestFixtures.public_client(@stub_name)

  describe "list/2" do
    test "asks for futures and keeps only the perpetuals" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api/v3/brokerage/market/products"
        assert conn.query_string == "product_type=FUTURE&limit=1000"
        refute Enum.any?(conn.req_headers, fn {k, _} -> k == "authorization" end)

        Req.Test.json(conn, %{
          "products" => [RestFixtures.perpetual_product(), RestFixtures.dated_future_product()]
        })
      end)

      assert {:ok, [%{product_id: "BIP-20DEC30-CDE"}]} = Perpetuals.list(client())
    end

    test "passes product_ids through" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.query_string ==
                 "product_type=FUTURE&limit=1000&product_ids=BIP-20DEC30-CDE&product_ids=ETP-20DEC30-CDE"

        Req.Test.json(conn, %{"products" => []})
      end)

      assert {:ok, []} =
               Perpetuals.list(client(), product_ids: ["BIP-20DEC30-CDE", "ETP-20DEC30-CDE"])
    end

    test "returns the error of a failed request" do
      Req.Test.expect(@stub_name, fn conn ->
        conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"error" => "boom"})
      end)

      assert {:error, _} = Perpetuals.list(client())
    end
  end

  describe "get/2" do
    test "returns a perpetual's snapshot" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.request_path == "/api/v3/brokerage/market/products/BIP-20DEC30-CDE"
        Req.Test.json(conn, RestFixtures.perpetual_product())
      end)

      assert {:ok, %{funding_interval_seconds: 3600}} =
               Perpetuals.get(client(), "BIP-20DEC30-CDE")
    end

    test "refuses a dated future" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, RestFixtures.dated_future_product())
      end)

      assert {:error, :not_perpetual} = Perpetuals.get(client(), "BIT-30OCT26-CDE")
    end

    test "returns not_found for an unknown product" do
      Req.Test.expect(@stub_name, fn conn ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"error" => "NOT_FOUND"})
      end)

      assert {:error, :not_found} = Perpetuals.get(client(), "NOPE")
    end
  end

  describe "snapshot/1" do
    test "parses open interest, funding, index price and basis" do
      snap = Perpetuals.snapshot(RestFixtures.perpetual_product())

      assert snap.base_asset == "BTC"
      assert Decimal.equal?(snap.open_interest, "186914")
      assert Decimal.equal?(snap.open_interest_base, "1869.14")
      assert Decimal.equal?(snap.open_interest_usd, Decimal.mult("1869.14", "81000"))
      assert Decimal.equal?(snap.funding_rate, "0.000008")
      assert snap.funding_time == ~U[2026-10-28 20:00:00Z]
      assert snap.funding_interval_seconds == 3600
      assert Decimal.equal?(snap.index_price, "81000")
      # (81220 - 81000) / 81000 * 100
      assert_in_delta Decimal.to_float(snap.basis_pct), 0.271605, 1.0e-6
      assert snap.listed_at == ~U[2025-07-18 13:00:00Z]
      refute snap.trading_disabled
    end

    test "reads empty strings as nil and leaves derived values nil" do
      product =
        put_in(RestFixtures.perpetual_product(), ["future_product_details", "index_price"], "")
        |> put_in(["future_product_details", "funding_rate"], "")

      snap = Perpetuals.snapshot(product)

      assert snap.index_price == nil
      assert snap.funding_rate == nil
      assert snap.basis_pct == nil
      assert snap.open_interest_usd == nil
      assert Decimal.equal?(snap.open_interest_base, "1869.14")
    end
  end

  describe "snapshot/1 with malformed values" do
    test "reads unparsable numbers, times and intervals, and a zero index, as nil" do
      product =
        RestFixtures.perpetual_product()
        |> Map.merge(%{"price" => "n/a", "new_at" => "yesterday"})
        |> put_in(["future_product_details", "index_price"], "0")
        |> put_in(["future_product_details", "funding_interval"], "1h")
        |> put_in(["future_product_details", "contract_root_unit"], "")

      snap = Perpetuals.snapshot(product)

      assert snap.price == nil
      assert snap.listed_at == nil
      assert snap.funding_interval_seconds == nil
      assert snap.base_asset == nil
      assert snap.basis_pct == nil
    end

    test "builds a snapshot with no future details at all" do
      assert %{open_interest: nil, funding_rate: nil} =
               Perpetuals.snapshot(%{"product_id" => "X"})
    end
  end

  describe "perpetual?/1" do
    test "is true only with a funding interval" do
      assert Perpetuals.perpetual?(RestFixtures.perpetual_product())
      refute Perpetuals.perpetual?(RestFixtures.dated_future_product())
      refute Perpetuals.perpetual?(%{"product_type" => "SPOT"})
    end
  end
end
