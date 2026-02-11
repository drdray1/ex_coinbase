defmodule ExCoinbase.Fees do
  @moduledoc """
  Coinbase Advanced Trade API - Fee and transaction summary.

  Provides functions to retrieve fee structure, transaction volume,
  and estimate fees for orders.

  ## Examples

      client = ExCoinbase.Client.new(api_key, private_key_pem)

      {:ok, summary} = ExCoinbase.Fees.get_transaction_summary(client)
      maker_rate = ExCoinbase.Fees.maker_fee_rate(summary)
      estimated = ExCoinbase.Fees.estimate_fee(summary, Decimal.new("1000"), false)
  """

  alias ExCoinbase.Client

  @type client :: Req.Request.t()
  @type response :: {:ok, map()} | {:error, term()}

  @doc """
  Retrieves transaction summary including fee tiers and volume.

  ## Options

    - `:product_type` - Filter by product type (e.g., "SPOT")
    - `:contract_expiry_type` - For futures (e.g., "EXPIRING")

  ## Examples

      iex> get_transaction_summary(client)
      {:ok, %{
        "total_volume" => 50000.00,
        "total_fees" => 125.50,
        "fee_tier" => %{"pricing_tier" => "Advanced", "maker_fee_rate" => "0.004", ...}
      }}
  """
  @spec get_transaction_summary(client(), keyword()) :: response()
  def get_transaction_summary(client, opts \\ []) do
    query = build_query(opts, [:product_type, :contract_expiry_type])

    client
    |> Req.get(url: "/transaction_summary", params: query)
    |> Client.handle_response()
  end

  @doc """
  Extracts the fee tier from transaction summary.
  """
  @spec extract_fee_tier(map()) :: map() | nil
  def extract_fee_tier(%{"fee_tier" => fee_tier}) when is_map(fee_tier), do: fee_tier
  def extract_fee_tier(_), do: nil

  @doc """
  Extracts maker fee rate as decimal.

  ## Examples

      iex> maker_fee_rate(%{"fee_tier" => %{"maker_fee_rate" => "0.004"}})
      #Decimal<0.004>
  """
  @spec maker_fee_rate(map()) :: Decimal.t()
  def maker_fee_rate(summary) do
    summary
    |> get_in(["fee_tier", "maker_fee_rate"])
    |> parse_decimal()
  end

  @doc """
  Extracts taker fee rate as decimal.

  ## Examples

      iex> taker_fee_rate(%{"fee_tier" => %{"taker_fee_rate" => "0.006"}})
      #Decimal<0.006>
  """
  @spec taker_fee_rate(map()) :: Decimal.t()
  def taker_fee_rate(summary) do
    summary
    |> get_in(["fee_tier", "taker_fee_rate"])
    |> parse_decimal()
  end

  @doc """
  Extracts total 30-day trading volume.
  """
  @spec total_volume(map()) :: Decimal.t()
  def total_volume(%{"total_volume" => volume}) when is_number(volume) do
    Decimal.from_float(volume)
  end

  def total_volume(%{"total_volume" => volume}) when is_binary(volume) do
    Decimal.new(volume)
  end

  def total_volume(_), do: Decimal.new("0")

  @doc """
  Extracts total fees paid.
  """
  @spec total_fees(map()) :: Decimal.t()
  def total_fees(%{"total_fees" => fees}) when is_number(fees) do
    Decimal.from_float(fees)
  end

  def total_fees(%{"total_fees" => fees}) when is_binary(fees) do
    Decimal.new(fees)
  end

  def total_fees(_), do: Decimal.new("0")

  @doc """
  Calculates estimated fee for a given order size.

  ## Parameters

    - `summary` - Transaction summary map
    - `order_size` - Order size in quote currency
    - `is_maker` - Whether order will be a maker (limit) or taker (market)

  ## Examples

      iex> estimate_fee(summary, Decimal.new("1000"), true)
      #Decimal<4.00>

      iex> estimate_fee(summary, Decimal.new("1000"), false)
      #Decimal<6.00>
  """
  @spec estimate_fee(map(), Decimal.t(), boolean()) :: Decimal.t()
  def estimate_fee(summary, order_size, is_maker) do
    fee_rate =
      if is_maker do
        maker_fee_rate(summary)
      else
        taker_fee_rate(summary)
      end

    Decimal.mult(order_size, fee_rate)
  end

  @doc """
  Returns the pricing tier name.
  """
  @spec pricing_tier(map()) :: String.t() | nil
  def pricing_tier(summary) do
    get_in(summary, ["fee_tier", "pricing_tier"])
  end

  @spec parse_decimal(String.t() | nil) :: Decimal.t()
  defp parse_decimal(nil), do: Decimal.new("0")
  defp parse_decimal(value) when is_binary(value), do: Decimal.new(value)
  defp parse_decimal(_), do: Decimal.new("0")

  @spec build_query(keyword(), list(atom())) :: keyword()
  defp build_query(opts, allowed_keys) do
    opts
    |> Keyword.take(allowed_keys)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end
end
