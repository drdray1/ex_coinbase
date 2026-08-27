defmodule ExCoinbase.JWT do
  @moduledoc """
  Generates JWT tokens for Coinbase CDP API authentication.

  Coinbase CDP Secret API Keys come in two flavours, both supported here:

  - **Ed25519** (current default when creating a key) — signed with `EdDSA`.
    CDP hands these out as a base64 string (32-byte seed or 64-byte seed+public
    key). A PKCS#8 `-----BEGIN PRIVATE KEY-----` PEM is also accepted.
  - **ECDSA P-256** (legacy) — signed with `ES256`. Supplied as an
    `-----BEGIN EC PRIVATE KEY-----` PEM.

  The signing algorithm is picked automatically from the key type.
  Each request requires a fresh JWT with the request URI included in the claims.

  ## Credentials Format

  - API Key ID: `organizations/{org_id}/apiKeys/{key_id}`
  - Private Key: Ed25519 base64 / PEM, or EC P-256 PEM

  ## JWT Structure

  Header:
  - alg: "EdDSA" or "ES256"
  - typ: "JWT"
  - kid: API Key ID
  - nonce: Random hex string

  Payload:
  - sub: API Key ID
  - iss: "cdp"
  - aud: ["cdp_service"]
  - nbf: Current timestamp
  - exp: Current timestamp + 120 seconds
  - uri: "{METHOD} {host}{path}" (REST only; omitted for WebSocket JWTs)
  """

  @token_expiry_seconds 120
  @nonce_length 16
  @ed25519_seed_bytes 32

  @doc """
  Generates a JWT token for authenticating a request to the Coinbase CDP API.

  ## Parameters

    - `api_key_id` - The API Key ID (format: `organizations/{org_id}/apiKeys/{key_id}`)
    - `private_key` - Ed25519 (base64 or PEM) or EC P-256 PEM private key
    - `method` - HTTP method (GET, POST, etc.)
    - `host` - The API host (e.g., "api.coinbase.com")
    - `path` - The request path (e.g., "/api/v3/brokerage/accounts")

  ## Returns

    - `{:ok, jwt}` - The signed JWT token
    - `{:error, reason}` - If signing fails

  ## Examples

      iex> ExCoinbase.JWT.generate_token(
      ...>   "organizations/abc/apiKeys/123",
      ...>   private_key,
      ...>   "GET",
      ...>   "api.coinbase.com",
      ...>   "/api/v3/brokerage/accounts"
      ...> )
      {:ok, "eyJhbGciOiJFZERTQSI..."}
  """
  @spec generate_token(String.t(), String.t(), String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def generate_token(api_key_id, private_key, method, host, path) do
    uri = "#{String.upcase(method)} #{host}#{path}"
    sign(api_key_id, private_key, %{"uri" => uri})
  end

  @doc """
  Generates a JWT token for Coinbase WebSocket authentication.

  WebSocket JWTs differ from REST API JWTs — they do not include a URI claim
  since WebSocket connections are not tied to specific HTTP endpoints.

  ## Parameters

    - `api_key_id` - The API Key ID (format: `organizations/{org_id}/apiKeys/{key_id}`)
    - `private_key` - Ed25519 (base64 or PEM) or EC P-256 PEM private key

  ## Returns

    - `{:ok, jwt}` - The signed JWT token
    - `{:error, reason}` - If signing fails
  """
  @spec generate_ws_jwt(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def generate_ws_jwt(api_key_id, private_key) do
    sign(api_key_id, private_key, %{})
  end

  @doc """
  Parses a private key into a JOSE JWK.

  Accepts:

    - EC P-256 PEM (`-----BEGIN EC PRIVATE KEY-----`)
    - PKCS#8 PEM (`-----BEGIN PRIVATE KEY-----`) containing an Ed25519 or EC key
    - Raw base64 Ed25519 key (32-byte seed or 64-byte seed + public key),
      which is the format the CDP portal provides for Ed25519 keys

  ## Returns

    - `{:ok, jwk}` - The parsed JWK
    - `{:error, reason}` - If parsing fails
  """
  @spec parse_private_key(String.t()) :: {:ok, JOSE.JWK.t()} | {:error, term()}
  def parse_private_key(key) when is_binary(key) do
    normalized = normalize_pem(key)

    if String.starts_with?(normalized, "-----BEGIN") do
      parse_pem(normalized)
    else
      parse_base64_ed25519(normalized)
    end
  end

  def parse_private_key(_), do: {:error, :invalid_pem_format}

  @doc """
  Returns the JWS algorithm to use for a parsed key: `"EdDSA"` for Ed25519,
  `"ES256"` for EC P-256.
  """
  @spec signing_alg(JOSE.JWK.t()) :: {:ok, String.t()} | {:error, :unsupported_private_key}
  def signing_alg(%JOSE.JWK{kty: {:jose_jwk_kty_okp_ed25519, _}}), do: {:ok, "EdDSA"}
  def signing_alg(%JOSE.JWK{kty: {:jose_jwk_kty_ec, _}}), do: {:ok, "ES256"}
  def signing_alg(_), do: {:error, :unsupported_private_key}

  # ============================================================================
  # Private Functions
  # ============================================================================

  @spec sign(String.t(), String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  defp sign(api_key_id, private_key, extra_claims) do
    now = System.system_time(:second)

    with {:ok, jwk} <- parse_private_key(private_key),
         {:ok, alg} <- signing_alg(jwk) do
      header = %{
        "alg" => alg,
        "typ" => "JWT",
        "kid" => api_key_id,
        "nonce" => generate_nonce()
      }

      payload =
        Map.merge(
          %{
            "sub" => api_key_id,
            "iss" => "cdp",
            "aud" => ["cdp_service"],
            "nbf" => now,
            "exp" => now + @token_expiry_seconds
          },
          extra_claims
        )

      jws = JOSE.JWS.from_map(header)
      {_, jwt} = JOSE.JWT.sign(jwk, jws, payload)
      {:ok, JOSE.JWS.compact(jwt) |> elem(1)}
    end
  end

  @spec parse_pem(String.t()) :: {:ok, JOSE.JWK.t()} | {:error, term()}
  defp parse_pem(pem) do
    case JOSE.JWK.from_pem(pem) do
      %JOSE.JWK{} = jwk -> check_supported(jwk)
      _ -> {:error, {:invalid_private_key, "unable to decode PEM"}}
    end
  rescue
    e -> {:error, {:invalid_private_key, Exception.message(e)}}
  end

  @spec parse_base64_ed25519(String.t()) :: {:ok, JOSE.JWK.t()} | {:error, term()}
  defp parse_base64_ed25519(encoded) do
    compact = String.replace(encoded, ~r/\s+/, "")

    case Base.decode64(compact) do
      {:ok, <<seed::binary-size(@ed25519_seed_bytes)>>} ->
        {:ok, ed25519_jwk(seed)}

      {:ok, <<seed::binary-size(@ed25519_seed_bytes), _pub::binary-size(@ed25519_seed_bytes)>>} ->
        {:ok, ed25519_jwk(seed)}

      {:ok, raw} ->
        {:error,
         {:invalid_private_key, "Ed25519 key must be 32 or 64 bytes, got #{byte_size(raw)}"}}

      :error ->
        {:error, {:invalid_private_key, "private key is neither PEM nor valid base64"}}
    end
  end

  @spec ed25519_jwk(binary()) :: JOSE.JWK.t()
  defp ed25519_jwk(seed) do
    {pub, _} = :crypto.generate_key(:eddsa, :ed25519, seed)
    JOSE.JWK.from_okp({:Ed25519, seed <> pub})
  end

  @spec check_supported(JOSE.JWK.t()) :: {:ok, JOSE.JWK.t()} | {:error, term()}
  defp check_supported(jwk) do
    case signing_alg(jwk) do
      {:ok, _alg} -> {:ok, jwk}
      {:error, reason} -> {:error, reason}
    end
  end

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
