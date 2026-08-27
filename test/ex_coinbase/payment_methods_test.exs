defmodule ExCoinbase.PaymentMethodsTest do
  use ExUnit.Case, async: true

  alias ExCoinbase.Fixtures
  alias ExCoinbase.PaymentMethods
  alias ExCoinbase.RestFixtures

  @stub_name ExCoinbase.PaymentMethodsTest

  defp client, do: Fixtures.test_client(@stub_name)

  # ============================================================================
  # HTTP Endpoint Tests
  # ============================================================================

  describe "list/1" do
    test "gets /payment_methods" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api/v3/brokerage/payment_methods"
        assert conn.query_string == ""
        Req.Test.json(conn, RestFixtures.payment_methods_response())
      end)

      assert {:ok, %{"payment_methods" => methods}} = PaymentMethods.list(client())
      assert length(methods) == 2
    end

    test "returns error on unauthorized" do
      Req.Test.expect(@stub_name, fn conn ->
        conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"error" => "Unauthorized"})
      end)

      assert {:error, :unauthorized} = PaymentMethods.list(client())
    end
  end

  describe "get/2" do
    test "gets /payment_methods/{id}" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api/v3/brokerage/payment_methods/pm-1"
        Req.Test.json(conn, RestFixtures.payment_method_response())
      end)

      assert {:ok, %{"payment_method" => %{"id" => "pm-1"}}} =
               PaymentMethods.get(client(), "pm-1")
    end

    test "returns not_found for unknown id" do
      Req.Test.expect(@stub_name, fn conn ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"error" => "not found"})
      end)

      assert {:error, :not_found} = PaymentMethods.get(client(), "nope")
    end
  end

  # ============================================================================
  # Pure Function Tests
  # ============================================================================

  describe "extract_payment_methods/1" do
    test "extracts list from response" do
      methods = PaymentMethods.extract_payment_methods(RestFixtures.payment_methods_response())
      assert [%{"id" => "pm-1"}, %{"id" => "pm-2"}] = methods
    end

    test "returns empty list when missing or invalid" do
      assert PaymentMethods.extract_payment_methods(%{}) == []
      assert PaymentMethods.extract_payment_methods(%{"payment_methods" => nil}) == []
      assert PaymentMethods.extract_payment_methods(nil) == []
    end
  end
end
