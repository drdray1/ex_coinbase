defmodule ExCoinbase.Predictions.Kalshi do
  @moduledoc """
  Public Kalshi market catalogue, used to discover Coinbase prediction markets.

  Coinbase's prediction markets are Kalshi event contracts, but the Advanced
  Trade API offers no way to list them (`GET /products` never returns them and
  `GET /products/{id}` is 404). Kalshi's public REST API needs no key, and
  every Coinbase product ID is simply the Kalshi ticker plus `-KALSHI`:

      KXBTC15M-26AUG272300-00  ->  KXBTC15M-26AUG272300-00-KALSHI

  Prices from Kalshi are in dollars per contract (`yes_ask_dollars` etc.),
  the same 0–1 USD scale Coinbase uses.

  ## Examples

      {:ok, %{"markets" => markets}} =
        ExCoinbase.Predictions.Kalshi.list_markets(series_ticker: "KXBTC15M", status: "open")

      product_id = ExCoinbase.Predictions.Kalshi.to_product_id(hd(markets)["ticker"])
      {:ok, _} = ExCoinbase.buy_yes(client, product_id, "5")
  """

  alias ExCoinbase.{Client, Query}

  @type response :: {:ok, map()} | {:error, term()}

  @default_base_url "https://api.elections.kalshi.com/trade-api/v2"
  @product_id_suffix "-KALSHI"

  @list_markets_keys [
    :limit,
    :cursor,
    :event_ticker,
    :series_ticker,
    :status,
    :tickers,
    :min_close_ts,
    :max_close_ts
  ]
  @list_events_keys [:limit, :cursor, :series_ticker, :status, :with_nested_markets]
  @list_series_keys [:category, :tags]

  @doc """
  Builds a Req client for the Kalshi public API.

  ## Options

    - `:base_url` - Override the API root (default `#{@default_base_url}`;
      also configurable via `config :ex_coinbase, :config, kalshi_url: ...`)
    - `:plug` - Test plug for `Req.Test`
    - `:req_options` - Extra `Req.new/1` options merged last (e.g. `retry: false`);
      also configurable via `config :ex_coinbase, :config, kalshi_req_options: [...]`
  """
  @spec client(keyword()) :: Req.Request.t()
  def client(opts \\ []) do
    config = Application.get_env(:ex_coinbase, :config, [])
    base_url = Keyword.get(opts, :base_url, Keyword.get(config, :kalshi_url, @default_base_url))
    req_options = Keyword.get(opts, :req_options, Keyword.get(config, :kalshi_req_options, []))

    [
      base_url: base_url,
      receive_timeout: Client.timeout(),
      retry: :transient,
      max_retries: 2
    ]
    |> maybe_plug(Keyword.get(opts, :plug))
    |> Keyword.merge(req_options)
    |> Req.new()
  end

  @doc """
  Lists markets (`GET /markets`).

  ## Options

    - `:series_ticker` - e.g. `"KXBTC15M"` (BTC price up/down every 15 minutes)
    - `:event_ticker`, `:tickers` (list), `:status` (`"open"`, `"closed"`, `"settled"`),
      `:min_close_ts`, `:max_close_ts`, `:limit` (max 1000), `:cursor`
    - `:client` - A client from `client/1` (default: a fresh one)

  Returns `{:ok, %{"markets" => [...], "cursor" => ...}}`.
  """
  @spec list_markets(keyword()) :: response()
  def list_markets(opts \\ []) do
    {client, opts} = pop_client(opts)

    client
    |> Req.get(url: Query.url("/markets", opts, @list_markets_keys))
    |> Client.handle_response()
  end

  @doc "Fetches one market by Kalshi ticker (`GET /markets/{ticker}`). Accepts a Coinbase product ID too."
  @spec get_market(String.t(), keyword()) :: response()
  def get_market(ticker, opts \\ []) do
    {client, _opts} = pop_client(opts)

    client
    |> Req.get(url: "/markets/#{from_product_id(ticker)}")
    |> Client.handle_response()
  end

  @doc """
  Lists events (`GET /events`). Options: `:series_ticker`, `:status`, `:limit`,
  `:cursor`, `:with_nested_markets`, `:client`.
  """
  @spec list_events(keyword()) :: response()
  def list_events(opts \\ []) do
    {client, opts} = pop_client(opts)

    client
    |> Req.get(url: Query.url("/events", opts, @list_events_keys))
    |> Client.handle_response()
  end

  @doc "Lists series (`GET /series`). Options: `:category` (e.g. `\"Crypto\"`), `:tags`, `:client`."
  @spec list_series(keyword()) :: response()
  def list_series(opts \\ []) do
    {client, opts} = pop_client(opts)

    client
    |> Req.get(url: Query.url("/series", opts, @list_series_keys))
    |> Client.handle_response()
  end

  @doc """
  Converts a Kalshi ticker to the Coinbase product ID (idempotent).

      iex> ExCoinbase.Predictions.Kalshi.to_product_id("KXBTC15M-26AUG272300-00")
      "KXBTC15M-26AUG272300-00-KALSHI"
  """
  @spec to_product_id(String.t()) :: String.t()
  def to_product_id(ticker) when is_binary(ticker) do
    if String.ends_with?(ticker, @product_id_suffix),
      do: ticker,
      else: ticker <> @product_id_suffix
  end

  @doc """
  Converts a Coinbase product ID back to the Kalshi ticker (idempotent).

      iex> ExCoinbase.Predictions.Kalshi.from_product_id("KXBTC15M-26AUG272300-00-KALSHI")
      "KXBTC15M-26AUG272300-00"
  """
  @spec from_product_id(String.t()) :: String.t()
  def from_product_id(product_id) when is_binary(product_id) do
    String.replace_suffix(product_id, @product_id_suffix, "")
  end

  @doc "Adds `\"product_id\"` (the Coinbase ID) to a Kalshi market map."
  @spec with_product_id(map()) :: map()
  def with_product_id(%{"ticker" => ticker} = market),
    do: Map.put(market, "product_id", to_product_id(ticker))

  def with_product_id(market), do: market

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp pop_client(opts) do
    case Keyword.pop(opts, :client) do
      {nil, rest} -> {client(), rest}
      {client, rest} -> {client, rest}
    end
  end

  defp maybe_plug(opts, nil), do: opts
  defp maybe_plug(opts, plug), do: Keyword.put(opts, :plug, plug)
end
