defmodule ExCoinbase.Public do
  @moduledoc """
  Coinbase Advanced Trade API - Public market data endpoints.

  These endpoints require **no API key**. Build an unauthenticated client
  with `ExCoinbase.Client.public/1` and pass it to any function here.

  ## Examples

      client = ExCoinbase.Client.public()

      {:ok, %{"iso" => iso}} = ExCoinbase.Public.server_time(client)
      {:ok, %{"products" => products}} = ExCoinbase.Public.list_products(client, limit: 10)
      {:ok, %{"product" => product}} = ExCoinbase.Public.get_product(client, "BTC-USD")

      {:ok, %{"candles" => candles}} =
        ExCoinbase.Public.get_candles(client, "BTC-USD",
          start: "1700000000",
          end: "1700086400",
          granularity: "ONE_HOUR"
        )
  """

  alias ExCoinbase.Client
  alias ExCoinbase.Products
  alias ExCoinbase.Query

  @type client :: Req.Request.t()
  @type response :: {:ok, map()} | {:error, term()}

  @list_products_keys [
    :limit,
    :offset,
    :product_type,
    :product_ids,
    :contract_expiry_type,
    :expiring_contract_status,
    :get_all_products,
    :products_sort_order,
    :cursor,
    :futures_underlying_type,
    :user_country_code,
    :expired
  ]

  @doc """
  Returns the current server time.

  ## Examples

      iex> server_time(client)
      {:ok, %{"iso" => "2024-01-01T00:00:00Z", "epochSeconds" => "1704067200", ...}}
  """
  @spec server_time(client()) :: response()
  def server_time(client) do
    client
    |> Req.get(url: "/time")
    |> Client.handle_response()
  end

  @doc """
  Lists available products (trading pairs) without authentication.

  ## Options

    - `:limit` - Maximum number of products to return
    - `:offset` - Number of products to skip
    - `:product_type` - `"SPOT"` or `"FUTURE"`
    - `:product_ids` - List of product IDs to filter by
    - `:contract_expiry_type` - Futures contract expiry type
    - `:expiring_contract_status` - Expiring contract status filter
    - `:get_all_products` - Include all products
    - `:products_sort_order` - Sort order
    - `:cursor` - Pagination cursor
    - `:futures_underlying_type` - Futures underlying type
    - `:user_country_code` - Country code for availability filtering
    - `:expired` - Include expired products

  ## Examples

      iex> list_products(client, product_ids: ["BTC-USD", "ETH-USD"])
      {:ok, %{"products" => [...]}}
  """
  @spec list_products(client(), keyword()) :: response()
  def list_products(client, opts \\ []) do
    client
    |> Req.get(url: Query.url("/market/products", opts, @list_products_keys))
    |> Client.handle_response()
  end

  @doc """
  Retrieves a single product by ID without authentication.

  ## Examples

      iex> get_product(client, "BTC-USD")
      {:ok, %{"product_id" => "BTC-USD", "price" => "45000.00", ...}}
  """
  @spec get_product(client(), String.t()) :: response()
  def get_product(client, product_id) do
    client
    |> Req.get(url: "/market/products/#{product_id}")
    |> Client.handle_response()
  end

  @doc """
  Retrieves candlestick data for a product without authentication.

  ## Required options

    - `:start` - Start time as Unix timestamp string
    - `:end` - End time as Unix timestamp string
    - `:granularity` - Candle interval (see `ExCoinbase.Products.valid_granularities/0`)

  ## Optional

    - `:limit` - Maximum number of candles to return

  ## Examples

      iex> get_candles(client, "BTC-USD", start: "1700000000", end: "1700086400", granularity: "ONE_HOUR")
      {:ok, %{"candles" => [...]}}

      iex> get_candles(client, "BTC-USD", end: "1700086400", granularity: "ONE_HOUR")
      {:error, "start is required"}
  """
  @spec get_candles(client(), String.t(), keyword()) :: response() | {:error, String.t()}
  def get_candles(client, product_id, opts) do
    with {:ok, query} <- validate_candle_params(opts) do
      client
      |> Req.get(
        url:
          Query.url("/market/products/#{product_id}/candles", query, [
            :start,
            :end,
            :granularity,
            :limit
          ])
      )
      |> Client.handle_response()
    end
  end

  @doc """
  Retrieves recent market trades for a product without authentication.

  ## Options

    - `:limit` - Maximum number of trades to return
    - `:start` - Start time as Unix timestamp string
    - `:end` - End time as Unix timestamp string

  ## Examples

      iex> get_market_trades(client, "BTC-USD", limit: 10)
      {:ok, %{"trades" => [...], "best_bid" => "...", "best_ask" => "..."}}
  """
  @spec get_market_trades(client(), String.t(), keyword()) :: response()
  def get_market_trades(client, product_id, opts \\ []) do
    client
    |> Req.get(
      url: Query.url("/market/products/#{product_id}/ticker", opts, [:limit, :start, :end])
    )
    |> Client.handle_response()
  end

  @doc """
  Retrieves the order book for a product without authentication.

  ## Options

    - `:limit` - Number of price levels per side
    - `:aggregation_price_increment` - Price increment to aggregate levels by

  ## Examples

      iex> get_product_book(client, "BTC-USD", limit: 5)
      {:ok, %{"pricebook" => %{"bids" => [...], "asks" => [...]}}}
  """
  @spec get_product_book(client(), String.t(), keyword()) :: response()
  def get_product_book(client, product_id, opts \\ []) do
    query = Keyword.put(opts, :product_id, product_id)

    client
    |> Req.get(
      url:
        Query.url("/market/product_book", query, [
          :product_id,
          :limit,
          :aggregation_price_increment
        ])
    )
    |> Client.handle_response()
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  @spec validate_candle_params(keyword()) :: {:ok, keyword()} | {:error, String.t()}
  defp validate_candle_params(opts) do
    with {:ok, start_time} <- require_param(opts, :start, "start is required"),
         {:ok, end_time} <- require_param(opts, :end, "end is required"),
         {:ok, granularity} <- require_param(opts, :granularity, "granularity is required"),
         :ok <- validate_granularity(granularity) do
      {:ok, [start: start_time, end: end_time, granularity: granularity, limit: opts[:limit]]}
    end
  end

  @spec require_param(keyword(), atom(), String.t()) :: {:ok, term()} | {:error, String.t()}
  defp require_param(opts, key, message) do
    case Keyword.get(opts, key) do
      nil -> {:error, message}
      value -> {:ok, value}
    end
  end

  @spec validate_granularity(String.t()) :: :ok | {:error, String.t()}
  defp validate_granularity(granularity) do
    valid = Products.valid_granularities()

    if granularity in valid do
      :ok
    else
      {:error, "granularity must be one of: #{Enum.join(valid, ", ")}"}
    end
  end
end
