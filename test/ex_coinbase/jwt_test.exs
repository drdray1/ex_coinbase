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

  describe "Ed25519 keys" do
    alias ExCoinbase.Fixtures

    defp decode_header(token) do
      [header_b64 | _] = String.split(token, ".")
      {:ok, json} = Base.url_decode64(header_b64, padding: false)
      Jason.decode!(json)
    end

    test "parses a PKCS#8 Ed25519 PEM" do
      assert {:ok, %JOSE.JWK{kty: {:jose_jwk_kty_okp_ed25519, _}} = jwk} =
               JWT.parse_private_key(Fixtures.sample_ed25519_private_key_pem())

      assert {:ok, "EdDSA"} = JWT.signing_alg(jwk)
    end

    test "parses a base64 32-byte seed and 64-byte seed+pub to the same key" do
      {:ok, from_seed} = JWT.parse_private_key(Fixtures.sample_ed25519_base64_seed())
      {:ok, from_full} = JWT.parse_private_key(Fixtures.sample_ed25519_base64_key())
      {:ok, from_pem} = JWT.parse_private_key(Fixtures.sample_ed25519_private_key_pem())

      assert JOSE.JWK.to_okp(from_seed) == JOSE.JWK.to_okp(from_full)
      assert JOSE.JWK.to_okp(from_seed) == JOSE.JWK.to_okp(from_pem)
    end

    test "tolerates whitespace/newlines around a base64 key" do
      key = "  " <> Fixtures.sample_ed25519_base64_seed() <> "\n"
      assert {:ok, %JOSE.JWK{}} = JWT.parse_private_key(key)
    end

    test "rejects base64 of the wrong length" do
      assert {:error, {:invalid_private_key, msg}} = JWT.parse_private_key(Base.encode64("short"))
      assert msg =~ "32 or 64 bytes"
    end

    test "rejects strings that are neither PEM nor base64" do
      assert {:error, {:invalid_private_key, msg}} = JWT.parse_private_key("not a key!!")
      assert msg =~ "neither PEM nor valid base64"
    end

    test "signs REST tokens with EdDSA and they verify with the public key" do
      key = Fixtures.sample_ed25519_base64_seed()

      {:ok, token} =
        JWT.generate_token(
          @test_api_key_id,
          key,
          "GET",
          "api.coinbase.com",
          "/api/v3/brokerage/accounts"
        )

      assert decode_header(token)["alg"] == "EdDSA"

      {:ok, jwk} = JWT.parse_private_key(key)

      assert {true, %JOSE.JWT{fields: claims}, _} =
               JOSE.JWT.verify(JOSE.JWK.to_public(jwk), token)

      assert claims["uri"] == "GET api.coinbase.com/api/v3/brokerage/accounts"
      assert claims["aud"] == ["cdp_service"]
    end

    test "signs WebSocket tokens with EdDSA and omits the uri claim" do
      {:ok, token} =
        JWT.generate_ws_jwt(@test_api_key_id, Fixtures.sample_ed25519_private_key_pem())

      assert decode_header(token)["alg"] == "EdDSA"

      {:ok, jwk} = JWT.parse_private_key(Fixtures.sample_ed25519_private_key_pem())

      assert {true, %JOSE.JWT{fields: claims}, _} =
               JOSE.JWT.verify(JOSE.JWK.to_public(jwk), token)

      refute Map.has_key?(claims, "uri")
    end

    test "EC keys still sign with ES256" do
      {:ok, jwk} = JWT.parse_private_key(@test_private_key)
      assert {:ok, "ES256"} = JWT.signing_alg(jwk)
    end
  end

  describe "unsupported keys" do
    @rsa_pem """
    -----BEGIN RSA PRIVATE KEY-----
    MIIBPAIBAAJBAMPCVtPqD4dKOyhzKTx8bcG4538iOCGoVo3iHCnY1bIcVSbTBX27
    5FZAlgpRXo0f7XnoqX3N6ZmhSY2xtJ4VGHkCAwEAAQJAK6bsYbjx2YNOCckUSu6c
    MvSeepUQ20CEfIMNMK+vh1Wx82D2D45ueUnJh/7yT4pJBLCy9H5ghal4DVFfT6h4
    GQIhAPDw4TuTaiPpL2ciP87vfuDztSAVkw1AogrSiu6UgOvDAiEAz/6J0KIIoiAy
    K/emmBXtsgwKIbfOTgkDNYDLHHxJcxMCIQDTamoYPpfp/tkLZDAdQmVQukf6aTPp
    cwc8+9XQ1xnwxQIhAJ+e8Tba0xNQ8BAL+57l3Ufxs2jS/ZGnmv3ZfIa830VfAiEA
    prZ//zpx/HhUkgqBer4waDCeKBbf4IUAITtRjFc+pY8=
    -----END RSA PRIVATE KEY-----
    """

    test "RSA keys are rejected as unsupported" do
      assert {:error, :unsupported_private_key} = JWT.parse_private_key(@rsa_pem)
      assert {:error, :unsupported_private_key} = JWT.signing_alg(%JOSE.JWK{})
    end

    test "malformed PEM bodies are rejected" do
      pem = "-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----"
      assert {:error, {:invalid_private_key, _}} = JWT.parse_private_key(pem)
    end

    test "generate_token surfaces key errors" do
      assert {:error, :unsupported_private_key} =
               JWT.generate_token(@test_api_key_id, @rsa_pem, "GET", "api.coinbase.com", "/x")
    end
  end
end
