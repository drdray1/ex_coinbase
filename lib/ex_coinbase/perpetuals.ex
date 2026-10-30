defmodule ExCoinbase.Perpetuals do
  @moduledoc """
  Coinbase Advanced Trade API - US perpetual futures market state.

  Coinbase's US perpetuals (the CDE "nano" perps such as `BIP-20DEC30-CDE`,
  "BTC PERP") are listed as `FUTURE` products. Their `future_product_details`
  carry the live open interest, the next funding rate and time, the funding
  interval and the index price. This module turns those into a typed snapshot.

  These are **live values only**: Coinbase publishes no history of open
  interest, funding or index price, so a series has to be recorded by
  polling. They read the public `/market` endpoints, so a client from
  `ExCoinbase.Client.public/1` works, as does an authenticated one.

  Note that Coinbase reports these products with
  `contract_expiry_type: "EXPIRING"` (a far-dated 2030 expiry) and returns
  nothing for `contract_expiry_type: "PERPETUAL"`; a product is treated as a
  perpetual when it has a funding interval.

  ## Examples

      client = ExCoinbase.Client.public()

      {:ok, perps} = ExCoinbase.Perpetuals.list(client)
      {:ok, btc} = ExCoinbase.Perpetuals.get(client, "BIP-20DEC30-CDE")

      btc.open_interest       #=> Decimal.new("186914")  (contracts)
      btc.open_interest_base  #=> Decimal.new("1869.14") (BTC)
      btc.funding_rate        #=> Decimal.new("0.000008") (per funding interval)
      btc.basis_pct           #=> last price over index price, in percent
  """

  alias ExCoinbase.Client
  alias ExCoinbase.Query

  @type client :: Req.Request.t()

  @type snapshot :: %{
          product_id: String.t(),
          display_name: String.t() | nil,
          base_asset: String.t() | nil,
          contract_size: Decimal.t() | nil,
          price: Decimal.t() | nil,
          mid_price: Decimal.t() | nil,
          index_price: Decimal.t() | nil,
          settlement_price: Decimal.t() | nil,
          basis_pct: Decimal.t() | nil,
          open_interest: Decimal.t() | nil,
          open_interest_base: Decimal.t() | nil,
          open_interest_usd: Decimal.t() | nil,
          funding_rate: Decimal.t() | nil,
          funding_time: DateTime.t() | nil,
          funding_interval_seconds: pos_integer() | nil,
          volume_24h: Decimal.t() | nil,
          quote_volume_24h: Decimal.t() | nil,
          listed_at: DateTime.t() | nil,
          trading_disabled: boolean()
        }

  # Coinbase lists about 120 futures in all; one page holds every one.
  @page_limit 1000

  @doc """
  Lists every US perpetual as a snapshot.

  ## Options

    - `:product_ids` - Only these products

  ## Examples

      iex> list(client)
      {:ok, [%{product_id: "BIP-20DEC30-CDE", open_interest: Decimal.new("186914"), ...}]}
  """
  @spec list(client(), keyword()) :: {:ok, [snapshot()]} | {:error, term()}
  def list(client, opts \\ []) do
    query = [product_type: "FUTURE", limit: @page_limit, product_ids: opts[:product_ids]]

    with {:ok, response} <-
           client
           |> Req.get(
             url: Query.url("/market/products", query, [:product_type, :limit, :product_ids])
           )
           |> Client.handle_response() do
      products = Map.get(response, "products") || []
      {:ok, for(product <- products, perpetual?(product), do: snapshot(product))}
    end
  end

  @doc """
  Retrieves one perpetual's snapshot.

  Returns `{:error, :not_perpetual}` for a product that is not one, such as a
  dated future or a spot pair.

  ## Examples

      iex> get(client, "BIP-20DEC30-CDE")
      {:ok, %{product_id: "BIP-20DEC30-CDE", funding_rate: Decimal.new("0.000008"), ...}}

      iex> get(client, "BTC-USD")
      {:error, :not_perpetual}
  """
  @spec get(client(), String.t()) :: {:ok, snapshot()} | {:error, term()}
  def get(client, product_id) do
    with {:ok, product} <-
           client
           |> Req.get(url: "/market/products/#{product_id}")
           |> Client.handle_response() do
      if perpetual?(product), do: {:ok, snapshot(product)}, else: {:error, :not_perpetual}
    end
  end

  @doc """
  Whether a product (as the products endpoints return it) is a perpetual.

  ## Examples

      iex> perpetual?(%{"future_product_details" => %{"funding_interval" => "3600s"}})
      true

      iex> perpetual?(%{"product_type" => "SPOT"})
      false
  """
  @spec perpetual?(map()) :: boolean()
  def perpetual?(%{"future_product_details" => %{"funding_interval" => interval}})
      when is_binary(interval) and interval != "",
      do: true

  def perpetual?(_product), do: false

  @doc """
  Builds a snapshot from a perpetual product map.

  Numbers are `Decimal`s, and `nil` where Coinbase sends an empty string.
  `open_interest` is in contracts; `open_interest_base` multiplies it by the
  contract size, and `open_interest_usd` by the index price as well.
  `basis_pct` is `(price - index_price) / index_price * 100`.
  """
  @spec snapshot(map()) :: snapshot()
  def snapshot(product) do
    details = Map.get(product, "future_product_details") || %{}
    contract_size = decimal(details["contract_size"])
    price = decimal(product["price"])
    index_price = decimal(details["index_price"])
    open_interest = decimal(details["open_interest"])
    open_interest_base = multiply(open_interest, contract_size)

    %{
      product_id: product["product_id"],
      display_name: product["display_name"],
      base_asset: blank_to_nil(details["contract_root_unit"]),
      contract_size: contract_size,
      price: price,
      mid_price: decimal(product["mid_market_price"]),
      index_price: index_price,
      settlement_price: decimal(details["settlement_price"]),
      basis_pct: basis_pct(price, index_price),
      open_interest: open_interest,
      open_interest_base: open_interest_base,
      open_interest_usd: multiply(open_interest_base, index_price),
      funding_rate: decimal(details["funding_rate"]),
      funding_time: datetime(details["funding_time"]),
      funding_interval_seconds: seconds(details["funding_interval"]),
      volume_24h: decimal(product["volume_24h"]),
      quote_volume_24h: decimal(product["approximate_quote_24h_volume"]),
      listed_at: datetime(product["new_at"]),
      trading_disabled: product["trading_disabled"] == true
    }
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp decimal(value) when is_binary(value) and value != "" do
    case Decimal.parse(value) do
      {decimal, ""} -> decimal
      _ -> nil
    end
  end

  defp decimal(_value), do: nil

  defp datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp datetime(_value), do: nil

  # Coinbase writes durations as protobuf strings such as "3600s".
  defp seconds(value) when is_binary(value) do
    case Integer.parse(value) do
      {seconds, "s"} when seconds > 0 -> seconds
      _ -> nil
    end
  end

  defp seconds(_value), do: nil

  defp blank_to_nil(value) when is_binary(value) and value != "", do: value
  defp blank_to_nil(_value), do: nil

  defp multiply(%Decimal{} = a, %Decimal{} = b), do: Decimal.mult(a, b)
  defp multiply(_a, _b), do: nil

  defp basis_pct(%Decimal{} = price, %Decimal{} = index) do
    if Decimal.gt?(index, 0) do
      price |> Decimal.sub(index) |> Decimal.div(index) |> Decimal.mult(100)
    end
  end

  defp basis_pct(_price, _index), do: nil
end
