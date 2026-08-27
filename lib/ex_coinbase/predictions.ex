defmodule ExCoinbase.Predictions do
  @moduledoc """
  Coinbase prediction markets (event contracts) via the Advanced Trade API.

  Prediction markets have no dedicated endpoints: they are traded through the
  regular order endpoints with a `prediction_metadata` field that selects the
  YES or NO side. This module wraps `ExCoinbase.Orders`, `ExCoinbase.Products`
  and `ExCoinbase.Portfolio` with that vocabulary.

  ## How contracts work

  - Each contract settles at 1 USD if the event resolves in its favour, else 0,
    so prices are quoted between 0 and 1 USD.
  - There is only a YES order book. A NO order is a short position on the YES
    book — the API handles that translation when you pass
    `prediction_side: "PREDICTION_SIDE_NO"`.
  - `base_size` is a number of contracts; `quote_size` is a USD amount.
  - Positions show up in the portfolio breakdown under
    `prediction_markets_positions` with `side` LONG (YES) or SHORT (NO).

  ## Examples

      client = ExCoinbase.new(api_key, private_key)

      # Find markets
      {:ok, markets} = ExCoinbase.Predictions.list_markets(client)

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

  @type client :: Req.Request.t()
  @type response :: {:ok, map()} | {:error, term()}
  @type product_id :: String.t()

  @yes "PREDICTION_SIDE_YES"
  @no "PREDICTION_SIDE_NO"
  @position_product_type "PRODUCT_TYPE_PREDICTION_MARKETS"
  @prediction_metadata_keys [:est_average_filled_price, :supports_fractional_base_size]

  # ============================================================================
  # Order Placement
  # ============================================================================

  @doc """
  Buys YES contracts.

  `amount` is a USD `quote_size` for market orders, or a contract count
  (`base_size`) when `:limit_price` is given.

  ## Options

    - `:limit_price` - Place a `limit_limit_gtc` order at this price (0–1 USD);
      `amount` is then a number of contracts
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
  for a `limit_limit_gtc` order; otherwise a market IOC order is placed.
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
  Lists prediction-market products.

  Calls `ExCoinbase.Products.list_products/2` with `get_all_products: true`
  and keeps products for which `prediction_market?/1` is true. Pass
  `:filter` (a 1-arity predicate on the product map) to override the
  default detection, and any other `list_products` option to narrow the query.

  ## Examples

      iex> list_markets(client)
      {:ok, [%{"product_id" => ..., "product_type" => ...}]}
  """
  @spec list_markets(client(), keyword()) :: {:ok, list(map())} | {:error, term()}
  def list_markets(client, opts \\ []) do
    {filter, query_opts} = Keyword.pop(opts, :filter, &prediction_market?/1)
    query_opts = Keyword.put_new(query_opts, :get_all_products, true)

    with {:ok, response} <- Products.list_products(client, query_opts) do
      {:ok, response |> Products.extract_products() |> Enum.filter(filter)}
    end
  end

  @doc """
  Heuristic used by `list_markets/2`: true when the product's `product_type`
  or `product_venue` mentions prediction markets.
  """
  @spec prediction_market?(map()) :: boolean()
  def prediction_market?(product) when is_map(product) do
    Enum.any?(["product_type", "product_venue"], fn key ->
      value = product[key]
      is_binary(value) and String.contains?(value, "PREDICTION")
    end)
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
  Lists historical orders that carry a prediction side.

  Options are passed to `ExCoinbase.Orders.list_orders/2`; the result is
  filtered client-side on `prediction_side`.
  """
  @spec list_orders(client(), keyword()) :: {:ok, list(map())} | {:error, term()}
  def list_orders(client, opts \\ []) do
    with {:ok, response} <- Orders.list_orders(client, opts) do
      orders =
        response
        |> Orders.extract_orders()
        |> Enum.filter(&(&1["prediction_side"] in [@yes, @no]))

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
    case Keyword.get(opts, :limit_price) do
      nil when side == "BUY" -> %{market_market_ioc: %{quote_size: amount}}
      nil -> %{market_market_ioc: %{base_size: amount}}
      price -> %{limit_limit_gtc: %{base_size: amount, limit_price: price}}
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
end
