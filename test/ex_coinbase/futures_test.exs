defmodule ExCoinbase.FuturesTest do
  use ExUnit.Case, async: true

  alias ExCoinbase.Fixtures
  alias ExCoinbase.Futures
  alias ExCoinbase.RestFixtures

  @stub_name ExCoinbase.FuturesTest

  defp client, do: Fixtures.test_client(@stub_name)

  defp read_json_body(conn) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    {Jason.decode!(body), conn}
  end

  # ============================================================================
  # HTTP Endpoint Tests
  # ============================================================================

  describe "balance_summary/1" do
    test "gets /cfm/balance_summary" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api/v3/brokerage/cfm/balance_summary"
        Req.Test.json(conn, RestFixtures.balance_summary_response())
      end)

      assert {:ok, %{"balance_summary" => %{"futures_buying_power" => _}}} =
               Futures.balance_summary(client())
    end

    test "returns error on unauthorized" do
      Req.Test.expect(@stub_name, fn conn ->
        conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"error" => "Unauthorized"})
      end)

      assert {:error, :unauthorized} = Futures.balance_summary(client())
    end
  end

  describe "list_positions/1" do
    test "gets /cfm/positions" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api/v3/brokerage/cfm/positions"
        Req.Test.json(conn, RestFixtures.positions_response())
      end)

      assert {:ok, %{"positions" => [%{"product_id" => "BIT-28FEB25-CDE"}]}} =
               Futures.list_positions(client())
    end
  end

  describe "get_position/2" do
    test "gets /cfm/positions/{product_id}" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api/v3/brokerage/cfm/positions/BIT-28FEB25-CDE"
        Req.Test.json(conn, RestFixtures.position_response())
      end)

      assert {:ok, %{"position" => %{"product_id" => "BIT-28FEB25-CDE"}}} =
               Futures.get_position(client(), "BIT-28FEB25-CDE")
    end

    test "returns not_found for unknown position" do
      Req.Test.expect(@stub_name, fn conn ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"error" => "not found"})
      end)

      assert {:error, :not_found} = Futures.get_position(client(), "NOPE")
    end
  end

  describe "schedule_sweep/2" do
    test "posts usd_amount to /cfm/sweeps/schedule" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/api/v3/brokerage/cfm/sweeps/schedule"
        {body, conn} = read_json_body(conn)
        assert body == %{"usd_amount" => "100.00"}
        Req.Test.json(conn, %{"success" => true})
      end)

      assert {:ok, %{"success" => true}} = Futures.schedule_sweep(client(), "100.00")
    end
  end

  describe "list_sweeps/1" do
    test "gets /cfm/sweeps" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api/v3/brokerage/cfm/sweeps"
        Req.Test.json(conn, RestFixtures.sweeps_response())
      end)

      assert {:ok, %{"sweeps" => [%{"id" => "sweep-1"}]}} = Futures.list_sweeps(client())
    end
  end

  describe "cancel_sweep/1" do
    test "deletes /cfm/sweeps" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.method == "DELETE"
        assert conn.request_path == "/api/v3/brokerage/cfm/sweeps"
        Req.Test.json(conn, %{"success" => true})
      end)

      assert {:ok, %{"success" => true}} = Futures.cancel_sweep(client())
    end
  end

  describe "get_intraday_margin_setting/1" do
    test "gets /cfm/intraday/margin_setting" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api/v3/brokerage/cfm/intraday/margin_setting"
        Req.Test.json(conn, RestFixtures.margin_setting_response())
      end)

      assert {:ok, %{"setting" => "INTRADAY_MARGIN_SETTING_STANDARD"}} =
               Futures.get_intraday_margin_setting(client())
    end
  end

  describe "set_intraday_margin_setting/2" do
    test "posts setting to /cfm/intraday/margin_setting" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/api/v3/brokerage/cfm/intraday/margin_setting"
        {body, conn} = read_json_body(conn)
        assert body == %{"setting" => "INTRADAY_MARGIN_SETTING_INTRADAY"}
        Req.Test.json(conn, %{})
      end)

      assert {:ok, %{}} =
               Futures.set_intraday_margin_setting(client(), "INTRADAY_MARGIN_SETTING_INTRADAY")
    end

    test "rejects invalid setting without making a request" do
      assert {:error, {:validation_error, [message]}} =
               Futures.set_intraday_margin_setting(client(), "BOGUS")

      assert message =~ "INTRADAY_MARGIN_SETTING_STANDARD"
      assert message =~ "INTRADAY_MARGIN_SETTING_INTRADAY"
    end
  end

  describe "current_margin_window/2" do
    test "gets /cfm/intraday/current_margin_window" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api/v3/brokerage/cfm/intraday/current_margin_window"
        assert conn.query_string == ""
        Req.Test.json(conn, RestFixtures.margin_window_response())
      end)

      assert {:ok, %{"margin_window" => _}} = Futures.current_margin_window(client())
    end

    test "encodes margin_profile_type" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.query_string == "margin_profile_type=MARGIN_PROFILE_TYPE_RETAIL_REGULAR"
        Req.Test.json(conn, RestFixtures.margin_window_response())
      end)

      assert {:ok, _} =
               Futures.current_margin_window(client(),
                 margin_profile_type: "MARGIN_PROFILE_TYPE_RETAIL_REGULAR"
               )
    end
  end

  # ============================================================================
  # Pure Function Tests
  # ============================================================================

  describe "valid_intraday_margin_settings/0" do
    test "lists both settings" do
      assert Futures.valid_intraday_margin_settings() == [
               "INTRADAY_MARGIN_SETTING_STANDARD",
               "INTRADAY_MARGIN_SETTING_INTRADAY"
             ]
    end
  end

  describe "extract_balance_summary/1" do
    test "extracts summary map" do
      summary = Futures.extract_balance_summary(RestFixtures.balance_summary_response())
      assert summary["futures_buying_power"]["value"] == "5000.00"
    end

    test "returns nil when missing" do
      assert Futures.extract_balance_summary(%{}) == nil
      assert Futures.extract_balance_summary(nil) == nil
    end
  end

  describe "extract_positions/1" do
    test "extracts positions list" do
      assert [%{"product_id" => "BIT-28FEB25-CDE"}] =
               Futures.extract_positions(RestFixtures.positions_response())
    end

    test "returns empty list when missing" do
      assert Futures.extract_positions(%{}) == []
      assert Futures.extract_positions(nil) == []
    end
  end
end
