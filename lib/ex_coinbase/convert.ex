defmodule ExCoinbase.Convert do
  @moduledoc """
  Coinbase Advanced Trade API - Convert operations.

  Converts between a fiat currency and its stablecoin counterpart. Only the
  following pairs are supported (in either direction):

    - USD <-> USDC
    - USD <-> PYUSD
    - EUR <-> EURC

  The flow is: create a quote, then commit it before it expires.

  ## Examples

      client = ExCoinbase.Client.new(api_key, private_key_pem)

      {:ok, %{"trade" => %{"id" => trade_id}}} =
        ExCoinbase.Convert.create_quote(client, usd_account_uuid, usdc_account_uuid, "100.00")

      {:ok, _} = ExCoinbase.Convert.commit_trade(client, trade_id, usd_account_uuid, usdc_account_uuid)
  """

  alias ExCoinbase.Client
  alias ExCoinbase.Query

  @type client :: Req.Request.t()
  @type response :: {:ok, map()} | {:error, term()}

  @doc """
  Creates a convert quote between two accounts.

  ## Options

    - `:trade_incentive_metadata` - Map with `user_incentive_id` and/or `code_val`

  ## Examples

      iex> create_quote(client, "usd-account-uuid", "usdc-account-uuid", "100.00")
      {:ok, %{"trade" => %{"id" => "...", "status" => "TRADE_STATUS_CREATED", ...}}}
  """
  @spec create_quote(client(), String.t(), String.t(), String.t(), keyword()) :: response()
  def create_quote(client, from_account, to_account, amount, opts \\ []) do
    body =
      %{from_account: from_account, to_account: to_account, amount: amount}
      |> maybe_put(:trade_incentive_metadata, opts[:trade_incentive_metadata])

    client
    |> Req.post(url: "/convert/quote", json: body)
    |> Client.handle_response()
  end

  @doc """
  Retrieves a convert trade by ID.

  ## Examples

      iex> get_trade(client, "trade-id", "usd-account-uuid", "usdc-account-uuid")
      {:ok, %{"trade" => %{"id" => "trade-id", ...}}}
  """
  @spec get_trade(client(), String.t(), String.t(), String.t()) :: response()
  def get_trade(client, trade_id, from_account, to_account) do
    query = [from_account: from_account, to_account: to_account]

    client
    |> Req.get(url: Query.url("/convert/trade/#{trade_id}", query, [:from_account, :to_account]))
    |> Client.handle_response()
  end

  @doc """
  Commits a previously created convert quote.

  ## Examples

      iex> commit_trade(client, "trade-id", "usd-account-uuid", "usdc-account-uuid")
      {:ok, %{"trade" => %{"id" => "trade-id", "status" => "TRADE_STATUS_COMPLETED", ...}}}
  """
  @spec commit_trade(client(), String.t(), String.t(), String.t()) :: response()
  def commit_trade(client, trade_id, from_account, to_account) do
    client
    |> Req.post(
      url: "/convert/trade/#{trade_id}",
      json: %{from_account: from_account, to_account: to_account}
    )
    |> Client.handle_response()
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  @spec maybe_put(map(), atom(), term()) :: map()
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
