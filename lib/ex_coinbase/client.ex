defmodule ExCoinbase.Client do
  @moduledoc """
  HTTP client for Coinbase Advanced Trade API.

  Handles JWT/ECDSA (ES256) authentication and request/response formatting.
  All requests are signed using the API key and EC private key.

  ## API Key Format

  The API key should be in the format: `organizations/{org_id}/apiKeys/{key_id}`

  ## Private Key Format

  The private key should be a PEM-formatted EC private key:

      -----BEGIN EC PRIVATE KEY-----
      ...
      -----END EC PRIVATE KEY-----

  ## Usage

      client = ExCoinbase.Client.new("organizations/abc/apiKeys/123", pem_key)
      {:ok, accounts} = ExCoinbase.Accounts.list_accounts(client)
  """

  @type client :: Req.Request.t()
  @type response :: {:ok, map()} | {:error, term()}

  @doc """
  Creates a new Coinbase API client with JWT/ECDSA authentication.

  ## Parameters

    - `api_key` - Coinbase API key (format: `organizations/{org_id}/apiKeys/{key_id}`)
    - `private_key_pem` - EC private key in PEM format

  ## Options

    - `:sandbox` - Use sandbox environment (default: false)
    - `:plug` - Test plug for `Req.Test` (default: nil)

  ## Examples

      client = ExCoinbase.Client.new("organizations/abc/apiKeys/123", pem_key)

      # Sandbox mode
      client = ExCoinbase.Client.new("organizations/abc/apiKeys/123", pem_key, sandbox: true)

      # Testing with Req.Test
      client = ExCoinbase.Client.new(api_key, pem, plug: {Req.Test, MyStub})
  """
  @spec new(String.t(), String.t(), keyword()) :: client()
  def new(api_key, private_key_pem, opts \\ []) do
    sandbox = Keyword.get(opts, :sandbox, false)
    plug = Keyword.get(opts, :plug)

    req_opts =
      [
        base_url: base_url(sandbox),
        headers: [{"content-type", "application/json"}],
        retry: :transient,
        max_retries: 3,
        retry_delay: fn attempt -> 500 * Integer.pow(2, attempt - 1) end
      ]
      |> maybe_add_plug(plug)

    Req.new(req_opts)
    |> ExCoinbase.Auth.attach(api_key, private_key_pem, sandbox: sandbox)
  end

  @doc """
  Returns the base URL based on environment configuration.
  """
  @spec base_url(boolean()) :: String.t()
  def base_url(sandbox \\ false) do
    config = Application.get_env(:ex_coinbase, :config, [])

    if sandbox do
      Keyword.get(config, :sandbox_url, "https://api-sandbox.coinbase.com/api/v3/brokerage")
    else
      Keyword.get(config, :base_url, "https://api.coinbase.com/api/v3/brokerage")
    end
  end

  @doc """
  Returns the WebSocket URL for market data streaming.
  """
  @spec websocket_url() :: String.t()
  def websocket_url do
    config = Application.get_env(:ex_coinbase, :config, [])
    Keyword.get(config, :websocket_url, "wss://advanced-trade-ws.coinbase.com")
  end

  @doc """
  Returns the WebSocket URL for authenticated user data streaming.
  """
  @spec websocket_user_url() :: String.t()
  def websocket_user_url do
    config = Application.get_env(:ex_coinbase, :config, [])
    Keyword.get(config, :websocket_user_url, "wss://advanced-trade-ws-user.coinbase.com")
  end

  @doc """
  Returns the configured timeout in milliseconds.
  """
  @spec timeout() :: non_neg_integer()
  def timeout do
    config = Application.get_env(:ex_coinbase, :config, [])
    Keyword.get(config, :timeout, 30_000)
  end

  @doc """
  Validates that a private key is in the correct PEM format.

  ## Returns

    - `{:ok, :valid}` if the key is valid
    - `{:error, reason}` if the key is invalid
  """
  @spec validate_private_key(String.t()) :: {:ok, :valid} | {:error, term()}
  def validate_private_key(private_key_pem) do
    case ExCoinbase.JWT.parse_private_key(private_key_pem) do
      {:ok, _jwk} -> {:ok, :valid}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Verifies credentials by testing the API connection.

  ## Returns

    - `{:ok, accounts}` - On successful authentication
    - `{:error, reason}` - On failure
  """
  @spec verify_credentials(String.t(), String.t(), boolean()) :: response()
  def verify_credentials(api_key, private_key_pem, sandbox \\ false) do
    require Logger

    case validate_private_key(private_key_pem) do
      {:ok, :valid} ->
        client = new(api_key, private_key_pem, sandbox: sandbox)

        case Req.get(client, url: "/accounts") do
          {:ok, %Req.Response{status: 200, body: body}} ->
            {:ok, body}

          {:ok, %Req.Response{status: 401, body: body}} ->
            Logger.warning("Coinbase 401 response: #{inspect(body)}")
            {:error, :unauthorized}

          {:ok, %Req.Response{status: 403, body: body}} ->
            Logger.warning("Coinbase 403 response: #{inspect(body)}")
            {:error, :forbidden}

          {:ok, %Req.Response{status: 0, body: {:jwt_generation_failed, reason}}} ->
            Logger.error("Coinbase JWT generation failed: #{inspect(reason)}")
            {:error, {:invalid_credentials, reason}}

          {:ok, %Req.Response{status: status, body: body}} ->
            {:error, {:api_error, status, extract_error_message(body)}}

          {:error, reason} ->
            {:error, {:connection_error, reason}}
        end

      {:error, reason} ->
        Logger.error("Coinbase private key validation failed: #{inspect(reason)}")
        {:error, {:invalid_private_key, reason}}
    end
  end

  @doc """
  Handles API response and normalizes to standard format.
  """
  @spec handle_response({:ok, Req.Response.t()} | {:error, term()}) :: response()
  def handle_response({:ok, %Req.Response{status: status, body: body}}) when status in 200..299 do
    {:ok, body}
  end

  def handle_response({:ok, %Req.Response{status: 401}}) do
    {:error, :unauthorized}
  end

  def handle_response({:ok, %Req.Response{status: 403}}) do
    {:error, :forbidden}
  end

  def handle_response({:ok, %Req.Response{status: 404}}) do
    {:error, :not_found}
  end

  def handle_response({:ok, %Req.Response{status: 429}}) do
    {:error, :rate_limited}
  end

  def handle_response({:ok, %Req.Response{status: 0, body: {:jwt_generation_failed, reason}}}) do
    {:error, {:jwt_generation_failed, reason}}
  end

  def handle_response({:ok, %Req.Response{status: status, body: body}}) when status >= 400 do
    {:error, {:api_error, status, extract_error_message(body)}}
  end

  def handle_response({:error, reason}) do
    {:error, {:connection_error, reason}}
  end

  @doc """
  Performs a health check by validating credentials.
  """
  @spec healthcheck(client()) :: :ok | {:error, term()}
  def healthcheck(client) do
    case Req.get(client, url: "/accounts") do
      {:ok, %Req.Response{status: 200}} ->
        :ok

      {:ok, %Req.Response{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %Req.Response{status: 403}} ->
        {:error, :forbidden}

      {:ok, %Req.Response{status: 0, body: {:jwt_generation_failed, reason}}} ->
        {:error, {:jwt_error, reason}}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec extract_error_message(map() | term()) :: String.t()
  defp extract_error_message(%{"error" => error}) when is_binary(error), do: error
  defp extract_error_message(%{"message" => message}) when is_binary(message), do: message

  defp extract_error_message(%{"error" => %{"message" => message}}) when is_binary(message),
    do: message

  defp extract_error_message(_), do: "Unknown error"

  defp maybe_add_plug(opts, nil), do: opts
  defp maybe_add_plug(opts, plug), do: Keyword.put(opts, :plug, plug)
end
