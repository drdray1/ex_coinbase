defmodule ExCoinbase.Products do
  @moduledoc """
  Coinbase Advanced Trade API - Product and market data operations.

  Provides functions to retrieve product information, candles (OHLCV),
  market trades, order books, and best bid/ask prices.

  ## Examples

      client = ExCoinbase.Client.new(api_key, private_key_pem)

      {:ok, response} = ExCoinbase.Products.list_products(client, product_type: "SPOT")
      {:ok, candles_resp} = ExCoinbase.Products.get_candles(client, "BTC-USD",
        start: "2024-01-01T00:00:00Z",
        end: "2024-01-02T00:00:00Z",
        granularity: "ONE_HOUR"
      )
  """

  alias ExCoinbase.{Client, Query}

  @type client :: Req.Request.t()
  @type response :: {:ok, map()} | {:error, term()}
  @type product_id :: String.t()

  @valid_granularities ~w(ONE_MINUTE FIVE_MINUTE FIFTEEN_MINUTE THIRTY_MINUTE ONE_HOUR TWO_HOUR SIX_HOUR ONE_DAY)

  @product_query_keys [
    :limit,
    :offset,
    :cursor,
    :product_type,
    :product_ids,
    :contract_expiry_type,
    :expiring_contract_status,
    :get_tradability_status,
    :get_all_products,
    :products_sort_order,
    :futures_underlying_type,
    :user_country_code,
    :expired
  ]

  @doc """
  Lists all available products (trading pairs).

  ## Options

    - `:limit` - Maximum products to return
    - `:offset` - Pagination offset
    - `:cursor` - Pagination cursor
    - `:product_type` - Filter by type: SPOT (default), FUTURE, EQUITY, OPTION_GROUP, FUTURE_GROUP
    - `:product_ids` - List of specific product IDs
    - `:contract_expiry_type` - EXPIRING or PERPETUAL (futures)
    - `:expiring_contract_status` - STATUS_UNEXPIRED, STATUS_EXPIRED, STATUS_ALL
    - `:get_tradability_status` - Include tradability status (boolean)
    - `:get_all_products` - Return every product type, not just SPOT (boolean)
    - `:products_sort_order` - PRODUCTS_SORT_ORDER_VOLUME_24H_DESCENDING or
      PRODUCTS_SORT_ORDER_LIST_TIME_DESCENDING
    - `:futures_underlying_type` - e.g. FUTURES_UNDERLYING_TYPE_SPOT
    - `:user_country_code` - Country code filter
    - `:expired` - Include expired products (boolean)

  ## Examples

      iex> list_products(client)
      {:ok, %{"products" => [%{"product_id" => "BTC-USD", ...}]}}

      iex> list_products(client, product_type: "SPOT", limit: 10)
      {:ok, %{"products" => [...]}}
  """
  @spec list_products(client(), keyword()) :: response()
  def list_products(client, opts \\ []) do
    client
    |> Req.get(url: Query.url("/products", opts, @product_query_keys))
    |> Client.handle_response()
  end

  @doc """
  Retrieves a single product by ID.

  ## Examples

      iex> get_product(client, "BTC-USD")
      {:ok, %{"product_id" => "BTC-USD", "price" => "50000.00", ...}}
  """
  @spec get_product(client(), product_id()) :: response()
  def get_product(client, product_id) do
    client
    |> Req.get(url: "/products/#{product_id}")
    |> Client.handle_response()
  end

  @doc """
  Retrieves candle (OHLCV) data for a product.

  ## Required Options

    - `:start` - Start time (ISO8601 or Unix timestamp)
    - `:end` - End time (ISO8601 or Unix timestamp)
    - `:granularity` - Candle interval
    - `:limit` - Optional maximum number of candles

  Valid granularities: `ONE_MINUTE`, `FIVE_MINUTE`, `FIFTEEN_MINUTE`,
  `THIRTY_MINUTE`, `ONE_HOUR`, `TWO_HOUR`, `SIX_HOUR`, `ONE_DAY`

  ## Examples

      iex> get_candles(client, "BTC-USD",
      ...>   start: "2024-01-01T00:00:00Z",
      ...>   end: "2024-01-02T00:00:00Z",
      ...>   granularity: "ONE_HOUR"
      ...> )
      {:ok, %{"candles" => [%{"start" => ..., "open" => ..., ...}]}}
  """
  @spec get_candles(client(), product_id(), keyword()) :: response()
  def get_candles(client, product_id, opts) do
    with {:ok, query} <- validate_candle_params(opts) do
      client
      |> Req.get(
        url:
          Query.url("/products/#{product_id}/candles", query, [:start, :end, :granularity, :limit])
      )
      |> Client.handle_response()
    end
  end

  @doc """
  Retrieves market trades for a product.

  ## Options

    - `:limit` - Maximum trades to return (default: 100)
    - `:start` - Start time filter
    - `:end` - End time filter

  ## Examples

      iex> get_market_trades(client, "BTC-USD")
      {:ok, %{"trades" => [%{"trade_id" => "...", "price" => "50000", ...}]}}
  """
  @spec get_market_trades(client(), product_id(), keyword()) :: response()
  def get_market_trades(client, product_id, opts \\ []) do
    client
    |> Req.get(url: Query.url("/products/#{product_id}/ticker", opts, [:limit, :start, :end]))
    |> Client.handle_response()
  end

  @doc """
  Retrieves the best bid/ask for products.

  ## Examples

      iex> get_best_bid_ask(client, ["BTC-USD", "ETH-USD"])
      {:ok, %{"pricebooks" => [%{"product_id" => "BTC-USD", ...}]}}
  """
  @spec get_best_bid_ask(client(), list(product_id())) :: response()
  def get_best_bid_ask(client, product_ids) when is_list(product_ids) do
    client
    |> Req.get(url: Query.url("/best_bid_ask", [product_ids: product_ids], [:product_ids]))
    |> Client.handle_response()
  end

  @doc """
  Retrieves the order book for a product.

  ## Options

    - `:limit` - Number of levels (default: 50)
    - `:aggregation_price_increment` - Aggregate levels to this price increment

  ## Examples

      iex> get_product_book(client, "BTC-USD", limit: 10)
      {:ok, %{"pricebook" => %{"bids" => [...], "asks" => [...]}}}
  """
  @spec get_product_book(client(), product_id(), keyword()) :: response()
  def get_product_book(client, product_id, opts \\ []) do
    query = Keyword.put(opts, :product_id, product_id)

    client
    |> Req.get(
      url: Query.url("/product_book", query, [:product_id, :limit, :aggregation_price_increment])
    )
    |> Client.handle_response()
  end

  @doc """
  Returns the list of valid candle granularities.
  """
  @spec valid_granularities() :: list(String.t())
  def valid_granularities, do: @valid_granularities

  @doc """
  Extracts products list from response.

  ## Examples

      iex> extract_products(%{"products" => [%{"product_id" => "BTC-USD"}]})
      [%{"product_id" => "BTC-USD"}]
  """
  @spec extract_products(map()) :: list(map())
  def extract_products(%{"products" => products}) when is_list(products), do: products
  def extract_products(_), do: []

  @doc """
  Extracts candles from response.
  """
  @spec extract_candles(map()) :: list(map())
  def extract_candles(%{"candles" => candles}) when is_list(candles), do: candles
  def extract_candles(_), do: []

  @doc """
  Filters products by quote currency.

  ## Examples

      iex> filter_by_quote_currency(products, "USD")
      [%{"product_id" => "BTC-USD", ...}]
  """
  @spec filter_by_quote_currency(list(map()), String.t()) :: list(map())
  def filter_by_quote_currency(products, quote_currency) do
    Enum.filter(products, fn product ->
      product["quote_currency_id"] == quote_currency
    end)
  end

  @doc """
  Filters products by base currency.
  """
  @spec filter_by_base_currency(list(map()), String.t()) :: list(map())
  def filter_by_base_currency(products, base_currency) do
    Enum.filter(products, fn product ->
      product["base_currency_id"] == base_currency
    end)
  end

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
  defp require_param(opts, key, error_message) do
    case Keyword.get(opts, key) do
      nil -> {:error, error_message}
      value -> {:ok, value}
    end
  end

  @spec validate_granularity(String.t()) :: :ok | {:error, String.t()}
  defp validate_granularity(granularity) when granularity in @valid_granularities, do: :ok

  defp validate_granularity(_) do
    {:error, "granularity must be one of: #{Enum.join(@valid_granularities, ", ")}"}
  end
end
