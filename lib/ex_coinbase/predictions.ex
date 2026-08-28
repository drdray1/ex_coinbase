defmodule ExCoinbase.Predictions do
  @moduledoc """
  Coinbase prediction markets (event contracts) via the Advanced Trade API.

  Prediction markets have no dedicated endpoints: they are traded through the
  regular order endpoints with a `prediction_metadata` field that selects the
  YES or NO side. This module wraps `ExCoinbase.Orders`, `ExCoinbase.Products`
  and `ExCoinbase.Portfolio` with that vocabulary.

  ## How contracts work

  - Markets are Kalshi event contracts; product IDs are Kalshi tickers with a
    `-KALSHI` suffix, e.g. `KXBTC15M-26AUG270830-30-KALSHI`.
  - Each contract settles at 1 USD if the event resolves in its favour, else 0,
    so prices are quoted between 0 and 1 USD.
  - There is only a YES order book. A NO order is a short position on the YES
    book — the API handles that translation when you pass
    `prediction_side: "PREDICTION_SIDE_NO"`.
  - Market orders are fill-or-kill (`market_market_fok`), which is what the
    Coinbase app itself sends. `base_size` is a number of contracts;
    `quote_size` is a USD amount.
  - Orders and fills report `product_type: "PREDICTION_MARKET"`; positions
    show up in the portfolio breakdown under `prediction_markets_positions`
    with `side` LONG (YES) or SHORT (NO).
  - Prediction products are not included in the default product list; see
    `list_markets/2` and `get_market/2`.

  ## Examples

      client = ExCoinbase.new(api_key, private_key)

      # Find open BTC 15-minute markets (via Kalshi's public catalogue)
      {:ok, markets, _cursor} = ExCoinbase.Predictions.list_markets(client, series_ticker: "KXBTC15M")
      product_id = hd(markets)["product_id"]

      # Preview: how many YES contracts does $10 buy?
      {:ok, preview} = ExCoinbase.Predictions.preview_yes(client, product_id, "10")
      ExCoinbase.Predictions.extract_prediction_metadata(preview)["minimum_contracts"]

      # Buy $10 of YES at market
      {:ok, resp} = ExCoinbase.Predictions.buy_yes(client, product_id, "10")

      # Buy 20 NO contracts, limit 0.35 each
      {:ok, resp} = ExCoinbase.Predictions.buy_no(client, product_id, "20", limit_price: "0.35")

      # Sell 5 YES contracts at market
      {:ok, resp} = ExCoinbase.Predictions.sell_yes(client, product_id, "5")

      # Open positions
      {:ok, positions} = ExCoinbase.Predictions.list_positions(client, portfolio_uuid)
  """

  alias ExCoinbase.{Orders, Portfolio, Products}
  alias ExCoinbase.Predictions.Kalshi

  @type client :: Req.Request.t()
  @type response :: {:ok, map()} | {:error, term()}
  @type product_id :: String.t()

  @yes "PREDICTION_SIDE_YES"
  @no "PREDICTION_SIDE_NO"
  @position_product_type "PRODUCT_TYPE_PREDICTION_MARKETS"
  @order_product_type "PREDICTION_MARKET"
  @product_id_suffix "-KALSHI"
  @max_pages 50
  @prediction_metadata_keys [:est_average_filled_price, :supports_fractional_base_size]

  # ============================================================================
  # Order Placement
  # ============================================================================

  @doc """
  Buys YES contracts.

  `amount` is a USD `quote_size` for market (FOK) orders, or a contract
  count (`base_size`) when `:limit_price` or `contracts: true` is given.

  ## Options

    - `:limit_price` - Place a `limit_limit_gtc` order at this price (0–1 USD);
      `amount` is then a number of contracts
    - `:contracts` - When true, `amount` is a number of contracts (`base_size`)
      even for market orders
    - `:client_order_id` - Idempotency key
    - `:est_average_filled_price` - `preview_order_est_average_filled_price` from a preview
    - `:supports_fractional_base_size` - Boolean, forwarded to the API
    - `:preview_id` - Preview ID to associate with this order
  """
  @spec buy_yes(client(), product_id(), String.t(), keyword()) :: response()
  def buy_yes(client, product_id, amount, opts \\ []),
    do: Orders.create_order(client, order_params(product_id, "BUY", @yes, amount, opts))

  @doc "Buys NO contracts. Same arguments as `buy_yes/4`."
  @spec buy_no(client(), product_id(), String.t(), keyword()) :: response()
  def buy_no(client, product_id, amount, opts \\ []),
    do: Orders.create_order(client, order_params(product_id, "BUY", @no, amount, opts))

  @doc """
  Sells YES contracts.

  `contracts` is the number of contracts (`base_size`). Pass `:limit_price`
  for a `limit_limit_gtc` order; otherwise a market FOK order is placed.
  Accepts the same options as `buy_yes/4`.
  """
  @spec sell_yes(client(), product_id(), String.t(), keyword()) :: response()
  def sell_yes(client, product_id, contracts, opts \\ []),
    do: Orders.create_order(client, order_params(product_id, "SELL", @yes, contracts, opts))

  @doc "Sells NO contracts. Same arguments as `sell_yes/4`."
  @spec sell_no(client(), product_id(), String.t(), keyword()) :: response()
  def sell_no(client, product_id, contracts, opts \\ []),
    do: Orders.create_order(client, order_params(product_id, "SELL", @no, contracts, opts))

  @doc """
  Places a prediction-market order with explicit side/prediction side.

  Lower-level than the `buy_*`/`sell_*` helpers: `side` is "BUY" or "SELL",
  `prediction_side` is "PREDICTION_SIDE_YES" or "PREDICTION_SIDE_NO", and
  `order_configuration` is any configuration accepted by
  `ExCoinbase.Orders.create_order/2`.
  """
  @spec create_order(client(), product_id(), String.t(), String.t(), map(), keyword()) ::
          response()
  def create_order(client, product_id, side, prediction_side, order_configuration, opts \\ []) do
    with :ok <- validate_prediction_side(prediction_side) do
      Orders.create_order(
        client,
        base_params(product_id, side, prediction_side, order_configuration, opts)
      )
    end
  end

  # ============================================================================
  # Preview
  # ============================================================================

  @doc """
  Previews a YES buy without placing it. Same arguments as `buy_yes/4`.

  The response's `prediction_order_metadata` (see
  `extract_prediction_metadata/1`) reports contract counts and USD totals
  after slippage.
  """
  @spec preview_yes(client(), product_id(), String.t(), keyword()) :: response()
  def preview_yes(client, product_id, amount, opts \\ []) do
    side = Keyword.get(opts, :side, "BUY")
    Orders.preview_order(client, order_params(product_id, side, @yes, amount, opts))
  end

  @doc """
  Previews a NO buy without placing it. Same arguments as `buy_no/4`.
  Pass `side: "SELL"` to preview a sale.
  """
  @spec preview_no(client(), product_id(), String.t(), keyword()) :: response()
  def preview_no(client, product_id, amount, opts \\ []) do
    side = Keyword.get(opts, :side, "BUY")
    Orders.preview_order(client, order_params(product_id, side, @no, amount, opts))
  end

  # ============================================================================
  # Discovery & Positions
  # ============================================================================

  @doc """
  Lists tradeable prediction markets.

  The Advanced Trade API cannot enumerate prediction products, so this reads
  Kalshi's public catalogue (`ExCoinbase.Predictions.Kalshi.list_markets/1`)
  and adds a `"product_id"` (the Coinbase ID, `<ticker>-KALSHI`) to each
  market. The `client` argument is unused but kept so the facade stays uniform.

  ## Options

    - `:series_ticker` - e.g. `"KXBTC15M"`; `:event_ticker`; `:tickers`
    - `:status` - default `"open"`
    - `:limit`, `:cursor` - Kalshi pagination (cursor is returned in the second element)
    - `:kalshi_client` - client from `ExCoinbase.Predictions.Kalshi.client/1`

  ## Examples

      iex> list_markets(client, series_ticker: "KXBTC15M")
      {:ok, [%{"ticker" => "KXBTC15M-26AUG272300-00", "product_id" => "KXBTC15M-26AUG272300-00-KALSHI", ...}], "cursor..."}
  """
  @spec list_markets(client(), keyword()) ::
          {:ok, list(map()), String.t() | nil} | {:error, term()}
  def list_markets(_client, opts \\ []) do
    {kalshi_client, opts} = Keyword.pop(opts, :kalshi_client)

    opts =
      opts
      |> Keyword.put_new(:status, "open")
      |> maybe_put_kw(:client, kalshi_client)

    with {:ok, %{"markets" => markets} = response} <- Kalshi.list_markets(opts) do
      {:ok, Enum.map(markets, &Kalshi.with_product_id/1), response["cursor"]}
    end
  end

  @doc """
  Scans Coinbase's own product catalogue (`get_all_products`, all pages) for
  prediction products. As of August 2026 Coinbase returns none — prefer
  `list_markets/2` — but this is kept in case the catalogue starts including them.
  """
  @spec scan_coinbase_catalogue(client(), keyword()) :: {:ok, list(map())} | {:error, term()}
  def scan_coinbase_catalogue(client, opts \\ []) do
    {filter, opts} = Keyword.pop(opts, :filter, &prediction_market?/1)

    with {:ok, products} <- fetch_all_pages(client, Keyword.put(opts, :get_all_products, true)) do
      {:ok, Enum.filter(products, filter)}
    end
  end

  @doc """
  Fetches a single prediction market by Coinbase product ID or Kalshi ticker
  from the Kalshi catalogue (Coinbase's `GET /products/{id}` returns 404 for
  prediction products). The result includes `"product_id"`.
  """
  @spec get_market(client(), product_id(), keyword()) :: response()
  def get_market(_client, product_id, opts \\ []) do
    with {:ok, %{"market" => market}} <- Kalshi.get_market(product_id, opts) do
      {:ok, Kalshi.with_product_id(market)}
    end
  end

  @doc """
  True when a product map looks like a prediction market: `product_type`
  is `PREDICTION_MARKET`/`PRODUCT_TYPE_PREDICTION_MARKETS`, `product_type` or
  `product_venue` mentions PREDICTION, or the `product_id` ends in `-KALSHI`.
  """
  @spec prediction_market?(map()) :: boolean()
  def prediction_market?(product) when is_map(product) do
    id = product["product_id"]

    (is_binary(id) and String.ends_with?(id, @product_id_suffix)) or
      Enum.any?(["product_type", "product_venue"], fn key ->
        value = product[key]
        is_binary(value) and String.contains?(value, "PREDICTION")
      end)
  end

  @doc "True when a historical order/fill map is a prediction-market order."
  @spec prediction_order?(map()) :: boolean()
  def prediction_order?(order) when is_map(order) do
    order["prediction_side"] in [@yes, @no] or order["product_type"] == @order_product_type
  end

  @doc """
  Lists open prediction-market positions in a portfolio.

  Fetches the portfolio breakdown and returns its
  `prediction_markets_positions` list.
  """
  @spec list_positions(client(), String.t()) :: {:ok, list(map())} | {:error, term()}
  def list_positions(client, portfolio_uuid) do
    with {:ok, response} <- Portfolio.get_portfolio_breakdown(client, portfolio_uuid) do
      {:ok, extract_prediction_positions(response)}
    end
  end

  @doc """
  Lists historical prediction-market orders.

  Options are passed to `ExCoinbase.Orders.list_orders/2`; the result is
  filtered client-side with `prediction_order?/1`.
  """
  @spec list_orders(client(), keyword()) :: {:ok, list(map())} | {:error, term()}
  def list_orders(client, opts \\ []) do
    with {:ok, response} <- Orders.list_orders(client, opts) do
      orders =
        response
        |> Orders.extract_orders()
        |> Enum.filter(&prediction_order?/1)

      {:ok, orders}
    end
  end

  # ============================================================================
  # Extractors
  # ============================================================================

  @doc "Extracts `prediction_markets_positions` from a portfolio breakdown response."
  @spec extract_prediction_positions(map()) :: list(map())
  def extract_prediction_positions(%{"breakdown" => breakdown}) when is_map(breakdown),
    do: extract_prediction_positions(breakdown)

  def extract_prediction_positions(%{"prediction_markets_positions" => positions})
      when is_list(positions),
      do: positions

  def extract_prediction_positions(_), do: []

  @doc "Extracts `prediction_order_metadata` from an order preview response."
  @spec extract_prediction_metadata(map()) :: map() | nil
  def extract_prediction_metadata(%{"prediction_order_metadata" => meta}) when is_map(meta),
    do: meta

  def extract_prediction_metadata(_), do: nil

  @doc ~S|Filters positions by side: "LONG" (YES) or "SHORT" (NO).|
  @spec filter_by_side(list(map()), String.t()) :: list(map())
  def filter_by_side(positions, side) when side in ["LONG", "SHORT"] do
    wanted = "PREDICTION_MARKETS_POSITION_SIDE_" <> side

    Enum.filter(positions, fn position ->
      get_in(position, ["prediction_markets", "side"]) == wanted
    end)
  end

  @doc "The `product_type` value prediction-market positions carry."
  @spec position_product_type() :: String.t()
  def position_product_type, do: @position_product_type

  @doc "The `product_type` value prediction-market orders and fills carry."
  @spec order_product_type() :: String.t()
  def order_product_type, do: @order_product_type

  @doc "Returns valid prediction sides."
  @spec valid_sides() :: list(String.t())
  def valid_sides, do: [@yes, @no]

  # ============================================================================
  # Private Functions
  # ============================================================================

  @spec order_params(product_id(), String.t(), String.t(), String.t(), keyword()) :: map()
  defp order_params(product_id, side, prediction_side, amount, opts) do
    base_params(product_id, side, prediction_side, order_configuration(side, amount, opts), opts)
  end

  @spec base_params(product_id(), String.t(), String.t(), map(), keyword()) :: map()
  defp base_params(product_id, side, prediction_side, order_configuration, opts) do
    %{
      product_id: product_id,
      side: side,
      order_configuration: order_configuration,
      prediction_metadata: prediction_metadata(prediction_side, opts)
    }
    |> maybe_put(:client_order_id, opts[:client_order_id])
    |> maybe_put(:preview_id, opts[:preview_id])
  end

  @spec order_configuration(String.t(), String.t(), keyword()) :: map()
  defp order_configuration(side, amount, opts) do
    in_contracts? = side == "SELL" or Keyword.get(opts, :contracts, false)

    case Keyword.get(opts, :limit_price) do
      nil when in_contracts? -> %{market_market_fok: %{base_size: amount}}
      nil -> %{market_market_fok: %{quote_size: amount}}
      price -> %{limit_limit_gtc: %{base_size: amount, limit_price: price}}
    end
  end

  @spec fetch_all_pages(client(), keyword()) :: {:ok, list(map())} | {:error, term()}
  defp fetch_all_pages(client, opts), do: fetch_all_pages(client, opts, [], @max_pages)

  defp fetch_all_pages(_client, _opts, acc, 0), do: {:ok, Enum.reverse(acc)}

  defp fetch_all_pages(client, opts, acc, pages_left) do
    with {:ok, response} <- Products.list_products(client, opts) do
      acc = Enum.reverse(Products.extract_products(response), acc)

      case response["pagination"] do
        %{"has_next" => true, "next_cursor" => cursor} when is_binary(cursor) and cursor != "" ->
          fetch_all_pages(client, Keyword.put(opts, :cursor, cursor), acc, pages_left - 1)

        _ ->
          {:ok, Enum.reverse(acc)}
      end
    end
  end

  @spec prediction_metadata(String.t(), keyword()) :: map()
  defp prediction_metadata(prediction_side, opts) do
    Enum.reduce(@prediction_metadata_keys, %{prediction_side: prediction_side}, fn key, acc ->
      maybe_put(acc, api_key(key), opts[key])
    end)
  end

  defp api_key(:est_average_filled_price), do: :preview_order_est_average_filled_price
  defp api_key(key), do: key

  @spec validate_prediction_side(String.t()) :: :ok | {:error, term()}
  defp validate_prediction_side(side) when side in [@yes, @no], do: :ok

  defp validate_prediction_side(_),
    do: {:error, {:validation_error, ["prediction_side must be one of: #{@yes}, #{@no}"]}}

  @spec maybe_put(map(), atom(), term()) :: map()
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @spec maybe_put_kw(keyword(), atom(), term()) :: keyword()
  defp maybe_put_kw(opts, _key, nil), do: opts
  defp maybe_put_kw(opts, key, value), do: Keyword.put(opts, key, value)
end
