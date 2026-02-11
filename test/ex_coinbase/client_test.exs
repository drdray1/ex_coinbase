defmodule ExCoinbase.ClientTest do
  use ExUnit.Case, async: false
  use Mimic

  alias ExCoinbase.Client
  alias ExCoinbase.Fixtures

  setup :verify_on_exit!

  describe "new/3" do
    test "creates a Req.Request struct" do
      api_key = Fixtures.sample_api_key()
      private_key = Fixtures.sample_private_key_pem()

      client = Client.new(api_key, private_key)
      assert %Req.Request{} = client
    end

    test "creates client with sandbox option" do
      api_key = Fixtures.sample_api_key()
      private_key = Fixtures.sample_private_key_pem()

      client = Client.new(api_key, private_key, sandbox: true)
      assert %Req.Request{} = client
    end

    test "creates client with test plug" do
      api_key = Fixtures.sample_api_key()
      private_key = Fixtures.sample_private_key_pem()

      client = Client.new(api_key, private_key, plug: {Req.Test, __MODULE__})
      assert %Req.Request{} = client
    end
  end

  describe "base_url/1" do
    test "returns production URL by default" do
      url = Client.base_url(false)
      assert String.contains?(url, "api.coinbase.com")
      refute String.contains?(url, "sandbox")
    end

    test "returns sandbox URL when sandbox is true" do
      url = Client.base_url(true)
      assert String.contains?(url, "sandbox")
    end
  end

  describe "validate_private_key/1" do
    test "returns ok for valid EC private key" do
      private_key = Fixtures.sample_private_key_pem()
      assert {:ok, :valid} = Client.validate_private_key(private_key)
    end

    test "returns error for invalid PEM format" do
      assert {:error, :not_ec_private_key} = Client.validate_private_key(Fixtures.invalid_pem())
    end

    test "returns error for non-string input" do
      assert {:error, :invalid_pem_format} = Client.validate_private_key(nil)
      assert {:error, :invalid_pem_format} = Client.validate_private_key(123)
    end

    test "handles escaped newlines in PEM" do
      private_key =
        Fixtures.sample_private_key_pem()
        |> String.replace("\n", "\\n")

      assert {:ok, :valid} = Client.validate_private_key(private_key)
    end
  end

  describe "handle_response/1" do
    test "returns ok tuple for 200 status" do
      response = {:ok, %Req.Response{status: 200, body: %{"data" => "test"}}}
      assert {:ok, %{"data" => "test"}} = Client.handle_response(response)
    end

    test "returns ok tuple for 201 status" do
      response = {:ok, %Req.Response{status: 201, body: %{"created" => true}}}
      assert {:ok, %{"created" => true}} = Client.handle_response(response)
    end

    test "returns unauthorized error for 401 status" do
      response = {:ok, %Req.Response{status: 401, body: %{}}}
      assert {:error, :unauthorized} = Client.handle_response(response)
    end

    test "returns forbidden error for 403 status" do
      response = {:ok, %Req.Response{status: 403, body: %{}}}
      assert {:error, :forbidden} = Client.handle_response(response)
    end

    test "returns not_found error for 404 status" do
      response = {:ok, %Req.Response{status: 404, body: %{}}}
      assert {:error, :not_found} = Client.handle_response(response)
    end

    test "returns rate_limited error for 429 status" do
      response = {:ok, %Req.Response{status: 429, body: %{}}}
      assert {:error, :rate_limited} = Client.handle_response(response)
    end

    test "returns api_error for other 4xx/5xx errors" do
      response = {:ok, %Req.Response{status: 500, body: %{"error" => "Server error"}}}
      assert {:error, {:api_error, 500, "Server error"}} = Client.handle_response(response)
    end

    test "extracts message from nested error" do
      response =
        {:ok, %Req.Response{status: 400, body: %{"error" => %{"message" => "Bad request"}}}}

      assert {:error, {:api_error, 400, "Bad request"}} = Client.handle_response(response)
    end

    test "passes through connection error" do
      response = {:error, :timeout}
      assert {:error, {:connection_error, :timeout}} = Client.handle_response(response)
    end

    test "passes through JWT generation failure" do
      response =
        {:ok, %Req.Response{status: 0, body: {:jwt_generation_failed, :not_ec_private_key}}}

      assert {:error, {:jwt_generation_failed, :not_ec_private_key}} =
               Client.handle_response(response)
    end

    test "handles empty body in error response" do
      response = {:ok, %Req.Response{status: 500, body: %{}}}
      assert {:error, {:api_error, 500, "Unknown error"}} = Client.handle_response(response)
    end

    test "handles non-map body in error response" do
      response = {:ok, %Req.Response{status: 400, body: "Bad Request"}}
      assert {:error, {:api_error, 400, "Unknown error"}} = Client.handle_response(response)
    end
  end

  describe "verify_credentials/3" do
    test "returns error for invalid private key format" do
      api_key = Fixtures.sample_api_key()
      invalid_pem = Fixtures.invalid_pem()

      assert {:error, {:invalid_private_key, _}} = Client.verify_credentials(api_key, invalid_pem)
    end

    test "returns {:ok, body} for 200 response" do
      expect(Req, :get, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: %{"accounts" => []}}}
      end)

      api_key = Fixtures.sample_api_key()
      pem = Fixtures.sample_p256_private_key_pem()

      assert {:ok, %{"accounts" => []}} = Client.verify_credentials(api_key, pem)
    end

    test "returns {:error, :unauthorized} for 401 response" do
      expect(Req, :get, fn _client, _opts ->
        {:ok, %Req.Response{status: 401, body: %{"error" => "Unauthorized"}}}
      end)

      api_key = Fixtures.sample_api_key()
      pem = Fixtures.sample_p256_private_key_pem()

      assert {:error, :unauthorized} = Client.verify_credentials(api_key, pem)
    end

    test "returns {:error, :forbidden} for 403 response" do
      expect(Req, :get, fn _client, _opts ->
        {:ok, %Req.Response{status: 403, body: %{"error" => "Forbidden"}}}
      end)

      api_key = Fixtures.sample_api_key()
      pem = Fixtures.sample_p256_private_key_pem()

      assert {:error, :forbidden} = Client.verify_credentials(api_key, pem)
    end

    test "returns {:error, {:invalid_credentials, _}} for JWT generation failure" do
      expect(Req, :get, fn _client, _opts ->
        {:ok, %Req.Response{status: 0, body: {:jwt_generation_failed, :bad_key}}}
      end)

      api_key = Fixtures.sample_api_key()
      pem = Fixtures.sample_p256_private_key_pem()

      assert {:error, {:invalid_credentials, :bad_key}} = Client.verify_credentials(api_key, pem)
    end

    test "returns {:error, {:api_error, status, message}} for other errors" do
      expect(Req, :get, fn _client, _opts ->
        {:ok, %Req.Response{status: 500, body: %{"error" => "Internal error"}}}
      end)

      api_key = Fixtures.sample_api_key()
      pem = Fixtures.sample_p256_private_key_pem()

      assert {:error, {:api_error, 500, "Internal error"}} =
               Client.verify_credentials(api_key, pem)
    end

    test "returns {:error, {:connection_error, reason}} for connection failures" do
      expect(Req, :get, fn _client, _opts ->
        {:error, %Mint.TransportError{reason: :econnrefused}}
      end)

      api_key = Fixtures.sample_api_key()
      pem = Fixtures.sample_p256_private_key_pem()

      assert {:error, {:connection_error, _}} = Client.verify_credentials(api_key, pem)
    end
  end

  describe "healthcheck/1" do
    @stub_name ExCoinbase.ClientTest.Healthcheck

    test "returns :ok for 200 response" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, %{"accounts" => []})
      end)

      client = Fixtures.test_client(@stub_name)
      assert :ok = Client.healthcheck(client)
    end

    test "returns {:error, :unauthorized} for 401" do
      Req.Test.expect(@stub_name, fn conn ->
        conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{})
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:error, :unauthorized} = Client.healthcheck(client)
    end

    test "returns {:error, :forbidden} for 403" do
      Req.Test.expect(@stub_name, fn conn ->
        conn |> Plug.Conn.put_status(403) |> Req.Test.json(%{})
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:error, :forbidden} = Client.healthcheck(client)
    end

    test "returns {:error, {:unexpected_status, _}} for other status" do
      Req.Test.expect(@stub_name, fn conn ->
        conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{})
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:error, {:unexpected_status, 500}} = Client.healthcheck(client)
    end

    test "returns {:error, {:jwt_error, _}} for JWT generation failure" do
      expect(Req, :get, fn _client, _opts ->
        {:ok, %Req.Response{status: 0, body: {:jwt_generation_failed, :bad_key}}}
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:error, {:jwt_error, :bad_key}} = Client.healthcheck(client)
    end

    test "returns {:error, reason} for connection errors" do
      expect(Req, :get, fn _client, _opts ->
        {:error, %Mint.TransportError{reason: :timeout}}
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:error, %Mint.TransportError{reason: :timeout}} = Client.healthcheck(client)
    end
  end

  describe "websocket_url/0" do
    test "returns default websocket URL" do
      url = Client.websocket_url()
      assert String.contains?(url, "advanced-trade-ws.coinbase.com")
    end
  end

  describe "websocket_user_url/0" do
    test "returns default user websocket URL" do
      url = Client.websocket_user_url()
      assert String.contains?(url, "advanced-trade-ws-user.coinbase.com")
    end
  end

  describe "timeout/0" do
    test "returns default timeout" do
      assert Client.timeout() == 30_000
    end
  end
end
