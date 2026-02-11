defmodule ExCoinbase.FeesTest do
  use ExUnit.Case, async: true

  alias ExCoinbase.Fees
  alias ExCoinbase.Fixtures

  @stub_name ExCoinbase.FeesTest

  # ============================================================================
  # HTTP Endpoint Tests
  # ============================================================================

  describe "get_transaction_summary/2" do
    test "returns summary on success" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_transaction_summary_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"fee_tier" => _}} = Fees.get_transaction_summary(client)
    end

    test "returns error on unauthorized" do
      Req.Test.expect(@stub_name, fn conn ->
        conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"error" => "Unauthorized"})
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:error, :unauthorized} = Fees.get_transaction_summary(client)
    end
  end

  # ============================================================================
  # Pure Function Tests
  # ============================================================================

  describe "maker_fee_rate/1" do
    test "extracts maker fee rate as decimal" do
      summary = Fixtures.sample_transaction_summary_response()
      rate = Fees.maker_fee_rate(summary)
      assert Decimal.equal?(rate, Decimal.new("0.004"))
    end

    test "returns zero for missing fee tier" do
      rate = Fees.maker_fee_rate(%{})
      assert Decimal.equal?(rate, Decimal.new("0"))
    end
  end

  describe "taker_fee_rate/1" do
    test "extracts taker fee rate as decimal" do
      summary = Fixtures.sample_transaction_summary_response()
      rate = Fees.taker_fee_rate(summary)
      assert Decimal.equal?(rate, Decimal.new("0.006"))
    end
  end

  describe "total_volume/1" do
    test "extracts volume from float" do
      summary = Fixtures.sample_transaction_summary_response()
      volume = Fees.total_volume(summary)
      assert Decimal.gt?(volume, Decimal.new("0"))
    end

    test "extracts volume from string" do
      summary = Fixtures.sample_transaction_summary_string_response()
      volume = Fees.total_volume(summary)
      assert Decimal.equal?(volume, Decimal.new("50000.00"))
    end

    test "returns zero for missing volume" do
      assert Decimal.equal?(Fees.total_volume(%{}), Decimal.new("0"))
    end
  end

  describe "total_fees/1" do
    test "extracts fees from float" do
      summary = Fixtures.sample_transaction_summary_response()
      fees = Fees.total_fees(summary)
      assert Decimal.gt?(fees, Decimal.new("0"))
    end

    test "extracts fees from string" do
      summary = Fixtures.sample_transaction_summary_string_response()
      fees = Fees.total_fees(summary)
      assert Decimal.equal?(fees, Decimal.new("125.50"))
    end
  end

  describe "estimate_fee/3" do
    test "estimates maker fee" do
      summary = Fixtures.sample_transaction_summary_response()
      fee = Fees.estimate_fee(summary, Decimal.new("1000"), true)
      assert Decimal.equal?(fee, Decimal.new("4.000"))
    end

    test "estimates taker fee" do
      summary = Fixtures.sample_transaction_summary_response()
      fee = Fees.estimate_fee(summary, Decimal.new("1000"), false)
      assert Decimal.equal?(fee, Decimal.new("6.000"))
    end
  end

  describe "extract_fee_tier/1" do
    test "extracts fee tier" do
      summary = Fixtures.sample_transaction_summary_response()
      tier = Fees.extract_fee_tier(summary)
      assert tier["pricing_tier"] == "Advanced"
    end

    test "returns nil for missing fee tier" do
      assert Fees.extract_fee_tier(%{}) == nil
    end
  end

  describe "pricing_tier/1" do
    test "extracts pricing tier name" do
      summary = Fixtures.sample_transaction_summary_response()
      assert Fees.pricing_tier(summary) == "Advanced"
    end
  end
end
