defmodule ExCoinbase.JWTTest do
  use ExUnit.Case, async: true

  alias ExCoinbase.JWT

  # Test EC private key (P-256/prime256v1 curve) for JWT signing
  @test_private_key """
  -----BEGIN EC PRIVATE KEY-----
  MHcCAQEEIJu/Ze6KwFX6kqjf0YTCwuFtFwcaIA6NfRc2XaioC8DdoAoGCCqGSM49
  AwEHoUQDQgAE6ob5+ow9MXBF4R28xeIzj5djEWB9OM681bQ2IlqjV4LJAKdRyPRX
  7cjqMZo/TspePuKrd936h3l17oeU4qlgHw==
  -----END EC PRIVATE KEY-----
  """

  @test_api_key_id "organizations/test-org-123/apiKeys/test-key-456"

  describe "generate_token/5" do
    test "generates a valid JWT token" do
      {:ok, token} =
        JWT.generate_token(
          @test_api_key_id,
          @test_private_key,
          "GET",
          "api.coinbase.com",
          "/api/v3/brokerage/accounts"
        )

      assert is_binary(token)
      parts = String.split(token, ".")
      assert length(parts) == 3
    end

    test "includes correct header claims" do
      {:ok, token} =
        JWT.generate_token(
          @test_api_key_id,
          @test_private_key,
          "GET",
          "api.coinbase.com",
          "/accounts"
        )

      [header_b64 | _] = String.split(token, ".")
      {:ok, header_json} = Base.url_decode64(header_b64, padding: false)
      header = Jason.decode!(header_json)

      assert header["alg"] == "ES256"
      assert header["typ"] == "JWT"
      assert header["kid"] == @test_api_key_id
      assert is_binary(header["nonce"])
    end

    test "includes correct payload claims" do
      {:ok, token} =
        JWT.generate_token(
          @test_api_key_id,
          @test_private_key,
          "POST",
          "api.coinbase.com",
          "/api/v3/brokerage/orders"
        )

      [_, payload_b64 | _] = String.split(token, ".")
      {:ok, payload_json} = Base.url_decode64(payload_b64, padding: false)
      payload = Jason.decode!(payload_json)

      assert payload["sub"] == @test_api_key_id
      assert payload["iss"] == "cdp"
      assert payload["aud"] == ["cdp_service"]
      assert is_integer(payload["nbf"])
      assert is_integer(payload["exp"])
      assert payload["exp"] > payload["nbf"]
      assert payload["uri"] == "POST api.coinbase.com/api/v3/brokerage/orders"
    end

    test "generates different nonces for each token" do
      {:ok, token1} =
        JWT.generate_token(
          @test_api_key_id,
          @test_private_key,
          "GET",
          "api.coinbase.com",
          "/accounts"
        )

      {:ok, token2} =
        JWT.generate_token(
          @test_api_key_id,
          @test_private_key,
          "GET",
          "api.coinbase.com",
          "/accounts"
        )

      [header1_b64 | _] = String.split(token1, ".")
      [header2_b64 | _] = String.split(token2, ".")

      {:ok, header1_json} = Base.url_decode64(header1_b64, padding: false)
      {:ok, header2_json} = Base.url_decode64(header2_b64, padding: false)

      header1 = Jason.decode!(header1_json)
      header2 = Jason.decode!(header2_json)

      assert header1["nonce"] != header2["nonce"]
    end

    test "returns error for invalid private key" do
      malformed_key = "-----BEGIN EC PRIVATE KEY-----\nINVALID\n-----END EC PRIVATE KEY-----"

      result =
        JWT.generate_token(
          @test_api_key_id,
          malformed_key,
          "GET",
          "api.coinbase.com",
          "/accounts"
        )

      assert {:error, _reason} = result
    end
  end

  describe "parse_private_key/1" do
    test "parses valid PEM key" do
      {:ok, jwk} = JWT.parse_private_key(@test_private_key)
      assert %JOSE.JWK{} = jwk
    end

    test "handles escaped newlines from form input" do
      escaped_key =
        @test_private_key
        |> String.replace("\n", "\\n")

      {:ok, jwk} = JWT.parse_private_key(escaped_key)
      assert %JOSE.JWK{} = jwk
    end

    test "returns error for non-string input" do
      assert {:error, :invalid_pem_format} = JWT.parse_private_key(nil)
      assert {:error, :invalid_pem_format} = JWT.parse_private_key(123)
    end
  end

  describe "generate_ws_jwt/2" do
    test "generates valid JWT for WebSocket auth" do
      {:ok, token} = JWT.generate_ws_jwt(@test_api_key_id, @test_private_key)

      assert is_binary(token)
      parts = String.split(token, ".")
      assert length(parts) == 3
    end

    test "JWT has no URI claim" do
      {:ok, token} = JWT.generate_ws_jwt(@test_api_key_id, @test_private_key)

      [_, payload_b64 | _] = String.split(token, ".")
      {:ok, payload_json} = Base.url_decode64(payload_b64, padding: false)
      payload = Jason.decode!(payload_json)

      refute Map.has_key?(payload, "uri")
    end

    test "JWT expires in 120 seconds" do
      {:ok, token} = JWT.generate_ws_jwt(@test_api_key_id, @test_private_key)

      [_, payload_b64 | _] = String.split(token, ".")
      {:ok, payload_json} = Base.url_decode64(payload_b64, padding: false)
      payload = Jason.decode!(payload_json)

      assert payload["exp"] - payload["nbf"] == 120
    end

    test "includes required headers" do
      {:ok, token} = JWT.generate_ws_jwt(@test_api_key_id, @test_private_key)

      [header_b64 | _] = String.split(token, ".")
      {:ok, header_json} = Base.url_decode64(header_b64, padding: false)
      header = Jason.decode!(header_json)

      assert header["alg"] == "ES256"
      assert header["typ"] == "JWT"
      assert header["kid"] == @test_api_key_id
      assert is_binary(header["nonce"])
      assert String.length(header["nonce"]) == 32
    end

    test "returns error for invalid private key" do
      malformed_key = "-----BEGIN EC PRIVATE KEY-----\nINVALID\n-----END EC PRIVATE KEY-----"
      result = JWT.generate_ws_jwt(@test_api_key_id, malformed_key)
      assert {:error, _reason} = result
    end
  end
end
