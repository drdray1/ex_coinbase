defmodule ExCoinbase.Auth do
  @moduledoc """
  Req plugin for Coinbase CDP JWT authentication.

  Automatically generates and attaches a JWT token to each request
  using ES256 (ECDSA) signing as required by the Coinbase Advanced Trade API.

  ## Usage

  Typically used via `ExCoinbase.Client.new/3`, but can be attached manually:

      Req.new(base_url: "https://api.coinbase.com/api/v3/brokerage")
      |> ExCoinbase.Auth.attach(api_key, private_key_pem)
  """

  alias ExCoinbase.JWT

  @api_host "api.coinbase.com"
  @sandbox_host "api-sandbox.coinbase.com"
  @api_base_path "/api/v3/brokerage"

  @doc """
  Attaches JWT authentication to a Req request.

  ## Options

    - `:sandbox` - Use sandbox host for JWT URI (default: false)
  """
  @spec attach(Req.Request.t(), String.t(), String.t(), keyword()) :: Req.Request.t()
  def attach(request, api_key, private_key_pem, opts \\ []) do
    sandbox = Keyword.get(opts, :sandbox, false)

    request
    |> Req.Request.register_options([:coinbase_api_key, :coinbase_private_key, :coinbase_sandbox])
    |> Req.Request.merge_options(
      coinbase_api_key: api_key,
      coinbase_private_key: private_key_pem,
      coinbase_sandbox: sandbox
    )
    |> Req.Request.append_request_steps(coinbase_auth: &sign_request/1)
  end

  defp sign_request(request) do
    api_key = request.options[:coinbase_api_key]
    private_key_pem = request.options[:coinbase_private_key]
    sandbox = request.options[:coinbase_sandbox] || false

    if api_key && private_key_pem do
      method = request.method |> Atom.to_string() |> String.upcase()
      path = build_path(request)
      host = if sandbox, do: @sandbox_host, else: @api_host

      case JWT.generate_token(api_key, private_key_pem, method, host, path) do
        {:ok, jwt} ->
          Req.Request.put_header(request, "authorization", "Bearer #{jwt}")

        {:error, reason} ->
          {request, Req.Response.new(status: 0, body: {:jwt_generation_failed, reason})}
      end
    else
      request
    end
  end

  defp build_path(request) do
    url = request.url

    path =
      case url do
        %URI{path: path} when is_binary(path) -> path
        _ -> "/"
      end

    ensure_base_path(path)
  end

  defp ensure_base_path(path) when is_binary(path) do
    if String.starts_with?(path, @api_base_path) do
      path
    else
      @api_base_path <> path
    end
  end
end
