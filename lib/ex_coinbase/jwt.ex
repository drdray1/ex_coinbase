defmodule ExCoinbase.JWT do
  @moduledoc """
  Generates JWT tokens for Coinbase CDP API authentication.

  Coinbase CDP API uses JWT tokens signed with ES256 (ECDSA with P-256 curve).
  Each request requires a fresh JWT with the request URI included in the claims.

  ## Credentials Format

  - API Key ID: `organizations/{org_id}/apiKeys/{key_id}`
  - Private Key: EC Private Key in PEM format (ECDSA P-256)

  ## JWT Structure

  Header:
  - alg: "ES256"
  - typ: "JWT"
  - kid: API Key ID
  - nonce: Random hex string

  Payload:
  - sub: API Key ID
  - iss: "cdp"
  - aud: ["cdp_service"]
  - nbf: Current timestamp
  - exp: Current timestamp + 120 seconds
  - uri: "{METHOD} {host}{path}"
  """

  @token_expiry_seconds 120
  @nonce_length 16

  @doc """
  Generates a JWT token for authenticating a request to the Coinbase CDP API.

  ## Parameters

    - `api_key_id` - The API Key ID (format: `organizations/{org_id}/apiKeys/{key_id}`)
    - `private_key_pem` - The EC Private Key in PEM format
    - `method` - HTTP method (GET, POST, etc.)
    - `host` - The API host (e.g., "api.coinbase.com")
    - `path` - The request path (e.g., "/api/v3/brokerage/accounts")

  ## Returns

    - `{:ok, jwt}` - The signed JWT token
    - `{:error, reason}` - If signing fails

  ## Examples

      iex> ExCoinbase.JWT.generate_token(
      ...>   "organizations/abc/apiKeys/123",
      ...>   pem_key,
      ...>   "GET",
      ...>   "api.coinbase.com",
      ...>   "/api/v3/brokerage/accounts"
      ...> )
      {:ok, "eyJhbGciOiJFUzI1NiI..."}
  """
  @spec generate_token(String.t(), String.t(), String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def generate_token(api_key_id, private_key_pem, method, host, path) do
    now = System.system_time(:second)
    nonce = generate_nonce()
    uri = "#{String.upcase(method)} #{host}#{path}"

    header = %{
      "alg" => "ES256",
      "typ" => "JWT",
      "kid" => api_key_id,
      "nonce" => nonce
    }

    payload = %{
      "sub" => api_key_id,
      "iss" => "cdp",
      "aud" => ["cdp_service"],
      "nbf" => now,
      "exp" => now + @token_expiry_seconds,
      "uri" => uri
    }

    with {:ok, jwk} <- parse_private_key(private_key_pem) do
      jws = JOSE.JWS.from_map(header)
      {_, jwt} = JOSE.JWT.sign(jwk, jws, payload)
      {:ok, JOSE.JWS.compact(jwt) |> elem(1)}
    end
  end

  @doc """
  Generates a JWT token for Coinbase WebSocket authentication.

  WebSocket JWTs differ from REST API JWTs — they do not include a URI claim
  since WebSocket connections are not tied to specific HTTP endpoints.

  ## Parameters

    - `api_key_id` - The API Key ID (format: `organizations/{org_id}/apiKeys/{key_id}`)
    - `private_key_pem` - The EC Private Key in PEM format

  ## Returns

    - `{:ok, jwt}` - The signed JWT token
    - `{:error, reason}` - If signing fails
  """
  @spec generate_ws_jwt(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def generate_ws_jwt(api_key_id, private_key_pem) do
    now = System.system_time(:second)
    nonce = generate_nonce()

    header = %{
      "alg" => "ES256",
      "typ" => "JWT",
      "kid" => api_key_id,
      "nonce" => nonce
    }

    payload = %{
      "sub" => api_key_id,
      "iss" => "cdp",
      "aud" => ["cdp_service"],
      "nbf" => now,
      "exp" => now + @token_expiry_seconds
    }

    with {:ok, jwk} <- parse_private_key(private_key_pem) do
      jws = JOSE.JWS.from_map(header)
      {_, jwt} = JOSE.JWT.sign(jwk, jws, payload)
      {:ok, JOSE.JWS.compact(jwt) |> elem(1)}
    end
  end

  @doc """
  Parses an EC Private Key from PEM format into a JOSE JWK.

  ## Parameters

    - `pem` - The private key in PEM format

  ## Returns

    - `{:ok, jwk}` - The parsed JWK
    - `{:error, reason}` - If parsing fails
  """
  @spec parse_private_key(String.t()) :: {:ok, JOSE.JWK.t()} | {:error, term()}
  def parse_private_key(pem) when is_binary(pem) do
    normalized_pem = normalize_pem(pem)

    try do
      jwk = JOSE.JWK.from_pem(normalized_pem)

      case jwk do
        %JOSE.JWK{kty: {:jose_jwk_kty_ec, _}} -> {:ok, jwk}
        _ -> {:error, :not_ec_private_key}
      end
    rescue
      e -> {:error, {:invalid_private_key, Exception.message(e)}}
    end
  end

  def parse_private_key(_), do: {:error, :invalid_pem_format}

  @spec normalize_pem(String.t()) :: String.t()
  defp normalize_pem(pem) do
    pem
    |> String.replace("\\n", "\n")
    |> String.trim()
  end

  @spec generate_nonce() :: String.t()
  defp generate_nonce do
    :crypto.strong_rand_bytes(@nonce_length)
    |> Base.encode16(case: :lower)
  end
end
