defmodule ExCoinbase do
  @moduledoc """
  Elixir client for the Coinbase Advanced Trade API.

  Provides a unified interface for cryptocurrency trading, market data,
  account management, and real-time WebSocket streaming.

  ## Quick Start

      # Create a client with your API credentials
      client = ExCoinbase.new("organizations/org_id/apiKeys/key_id", private_key_pem)

      # Account operations
      {:ok, response} = ExCoinbase.list_accounts(client)

      # Market data
      {:ok, response} = ExCoinbase.list_products(client)
      {:ok, response} = ExCoinbase.get_candles(client, "BTC-USD",
        start: "2024-01-01T00:00:00Z",
        end: "2024-01-02T00:00:00Z",
        granularity: "ONE_HOUR"
      )

      # Trading
      {:ok, response} = ExCoinbase.market_order_quote(client, "BTC-USD", "BUY", "100")

  ## Configuration

  All configuration is optional — sensible defaults are provided:

      # config/config.exs
      config :ex_coinbase,
        config: [
          base_url: "https://api.coinbase.com/api/v3/brokerage",
          sandbox_url: "https://api-sandbox.coinbase.com/api/v3/brokerage",
          websocket_url: "wss://advanced-trade-ws.coinbase.com",
          websocket_user_url: "wss://advanced-trade-ws-user.coinbase.com",
          timeout: 30_000
        ]

  ## WebSocket Streaming

      {:ok, pid} = ExCoinbase.WebSocket.Connection.start_link(
        api_key_id: "organizations/org/apiKeys/key",
        private_key_pem: pem_key
      )

      ExCoinbase.WebSocket.Connection.add_subscriber(pid, self())
      ExCoinbase.WebSocket.Connection.subscribe(pid, ["BTC-USD", "ETH-USD"])

      # Receive: {:coinbase_user_event, %ExCoinbase.WebSocket.UserOrderEvent{...}}
  """

  alias ExCoinbase.{
    Accounts,
    Client,
    Fees,
    Orders,
    Portfolio,
    Products
  }

  # ============================================================================
  # Client
  # ============================================================================

  @doc """
  Creates a new Coinbase API client with authentication.

  ## Options

    - `:sandbox` - Use sandbox environment (default: false)
    - `:plug` - Test plug for `Req.Test` (default: nil)

  ## Examples

      client = ExCoinbase.new("organizations/abc/apiKeys/123", pem_key)

      client = ExCoinbase.new("organizations/abc/apiKeys/123", pem_key, sandbox: true)
  """
  def new(api_key, api_secret, opts \\ []) do
    Client.new(api_key, api_secret, opts)
  end

  @doc "Verifies API credentials by making a test request."
  defdelegate verify_credentials(api_key, api_secret, sandbox \\ false), to: Client

  @doc "Performs a health check on the client connection."
  defdelegate healthcheck(client), to: Client

  # ============================================================================
  # Accounts
  # ============================================================================

  @doc "Lists all accounts for the authenticated user."
  defdelegate list_accounts(client, opts \\ []), to: Accounts

  @doc "Retrieves a single account by UUID."
  defdelegate get_account(client, account_uuid), to: Accounts

  @doc "Extracts accounts list from response."
  defdelegate extract_accounts(response), to: Accounts

  @doc "Finds an account by currency code."
  defdelegate find_account_by_currency(accounts, currency),
    to: Accounts,
    as: :find_by_currency

  # ============================================================================
  # Products
  # ============================================================================

  @doc "Lists all available products (trading pairs)."
  defdelegate list_products(client, opts \\ []), to: Products

  @doc "Retrieves a single product by ID."
  defdelegate get_product(client, product_id), to: Products

  @doc "Retrieves candle (OHLCV) data for a product."
  defdelegate get_candles(client, product_id, opts), to: Products

  @doc "Retrieves market trades for a product."
  defdelegate get_market_trades(client, product_id, opts \\ []), to: Products

  @doc "Retrieves the best bid/ask for products."
  defdelegate get_best_bid_ask(client, product_ids), to: Products

  @doc "Retrieves the order book for a product."
  defdelegate get_product_book(client, product_id, opts \\ []), to: Products

  @doc "Extracts products list from response."
  defdelegate extract_products(response), to: Products

  @doc "Extracts candles from response."
  defdelegate extract_candles(response), to: Products

  @doc "Returns valid candle granularities."
  defdelegate valid_granularities(), to: Products

  # ============================================================================
  # Orders
  # ============================================================================

  @doc "Creates a new order with full configuration."
  defdelegate create_order(client, params), to: Orders

  @doc "Creates a market order using quote currency amount."
  defdelegate market_order_quote(client, product_id, side, quote_size), to: Orders

  @doc "Creates a market order using base currency amount."
  defdelegate market_order_base(client, product_id, side, base_size), to: Orders

  @doc "Creates a limit order with Good-Til-Canceled duration."
  defdelegate limit_order_gtc(client, product_id, side, base_size, limit_price), to: Orders

  @doc "Creates a limit order with Immediate-or-Cancel duration."
  defdelegate limit_order_ioc(client, product_id, side, base_size, limit_price), to: Orders

  @doc "Creates a limit order with Good-Til-Date duration."
  defdelegate limit_order_gtd(client, product_id, side, base_size, limit_price, end_time),
    to: Orders

  @doc "Creates a limit order with Fill-or-Kill duration."
  defdelegate limit_order_fok(client, product_id, side, base_size, limit_price), to: Orders

  @doc "Creates a stop-limit order with Good-Til-Canceled duration."
  defdelegate stop_limit_order_gtc(client, product_id, side, base_size, limit_price, stop_price),
    to: Orders

  @doc "Creates a stop-limit order with Good-Til-Date duration."
  defdelegate stop_limit_order_gtd(
                client,
                product_id,
                side,
                base_size,
                limit_price,
                stop_price,
                end_time
              ),
              to: Orders

  @doc """
  Creates a bracket order with entry limit, take-profit, and stop-loss (Good-Til-Canceled).

  When the entry fills, Coinbase activates TP and SL orders. When one exit leg fills,
  the other is automatically cancelled (OCO).
  """
  defdelegate bracket_order_gtc(
                client,
                product_id,
                side,
                base_size,
                entry_price,
                take_profit_price,
                stop_loss_price
              ),
              to: Orders

  @doc """
  Creates a bracket order with entry limit, take-profit, and stop-loss (Good-Til-Date).
  """
  defdelegate bracket_order_gtd(
                client,
                product_id,
                side,
                base_size,
                entry_price,
                take_profit_price,
                stop_loss_price,
                end_time
              ),
              to: Orders

  @doc "Edits an existing order's price and/or size."
  defdelegate edit_order(client, order_id, opts \\ []), to: Orders

  @doc "Previews an order edit without executing it."
  defdelegate edit_order_preview(client, order_id, opts \\ []), to: Orders

  @doc "Previews an order without executing it (fee/commission estimate)."
  defdelegate preview_order(client, params), to: Orders

  @doc "Closes an open position (full or partial)."
  defdelegate close_position(client, client_order_id, product_id, opts \\ []), to: Orders

  @doc "Cancels one or more orders."
  defdelegate cancel_orders(client, order_ids), to: Orders

  @doc "Cancels a single order."
  defdelegate cancel_order(client, order_id), to: Orders

  @doc "Lists orders with optional filtering."
  defdelegate list_orders(client, opts \\ []), to: Orders

  @doc "Retrieves a single order by ID."
  defdelegate get_order(client, order_id), to: Orders

  @doc "Lists fills (executed trades) with optional filtering."
  defdelegate list_fills(client, opts \\ []), to: Orders

  @doc "Extracts orders list from response."
  defdelegate extract_orders(response), to: Orders

  @doc "Extracts fills list from response."
  defdelegate extract_fills(response), to: Orders

  @doc "Validates order parameters."
  defdelegate validate_order_params(params), to: Orders

  @doc "Returns valid order sides."
  defdelegate valid_sides(), to: Orders

  @doc "Returns valid order types."
  defdelegate valid_order_types(), to: Orders

  @doc "Returns valid time-in-force values."
  defdelegate valid_time_in_force(), to: Orders

  # ============================================================================
  # Portfolio
  # ============================================================================

  @doc "Lists all portfolios."
  defdelegate list_portfolios(client, opts \\ []), to: Portfolio

  @doc "Creates a new portfolio."
  defdelegate create_portfolio(client, name), to: Portfolio

  @doc "Retrieves breakdown of a portfolio's holdings."
  defdelegate get_portfolio_breakdown(client, portfolio_uuid), to: Portfolio

  @doc "Moves funds between portfolios."
  defdelegate move_funds(client, params), to: Portfolio

  @doc "Deletes a portfolio."
  defdelegate delete_portfolio(client, portfolio_uuid), to: Portfolio

  @doc "Edits a portfolio's name."
  defdelegate edit_portfolio(client, portfolio_uuid, name), to: Portfolio

  @doc "Extracts portfolios list from response."
  defdelegate extract_portfolios(response), to: Portfolio

  @doc "Extracts spot positions from breakdown."
  defdelegate extract_spot_positions(breakdown), to: Portfolio

  # ============================================================================
  # Fees
  # ============================================================================

  @doc "Retrieves transaction summary including fee tiers and volume."
  defdelegate get_transaction_summary(client, opts \\ []), to: Fees

  @doc "Extracts maker fee rate from summary."
  defdelegate maker_fee_rate(summary), to: Fees

  @doc "Extracts taker fee rate from summary."
  defdelegate taker_fee_rate(summary), to: Fees

  @doc "Calculates estimated fee for an order."
  defdelegate estimate_fee(summary, order_size, is_maker), to: Fees

  # ============================================================================
  # Helpers
  # ============================================================================

  @doc """
  Extracts the first account ID from a list of accounts.

  ## Examples

      iex> ExCoinbase.extract_account_id([%{"uuid" => "abc-123"}])
      "abc-123"

      iex> ExCoinbase.extract_account_id([])
      nil
  """
  @spec extract_account_id(list(map())) :: String.t() | nil
  def extract_account_id([%{"uuid" => uuid} | _]), do: uuid
  def extract_account_id(_), do: nil

  @doc """
  Parses a product ID into base and quote currencies.

  ## Examples

      iex> ExCoinbase.parse_product_id("BTC-USD")
      {:ok, %{base: "BTC", quote: "USD"}}

      iex> ExCoinbase.parse_product_id("invalid")
      {:error, :invalid_format}
  """
  @spec parse_product_id(String.t()) :: {:ok, map()} | {:error, :invalid_format}
  def parse_product_id(product_id) do
    case String.split(product_id, "-") do
      [base, quote_currency] ->
        {:ok, %{base: base, quote: quote_currency}}

      _ ->
        {:error, :invalid_format}
    end
  end

  @doc """
  Builds a product ID from base and quote currencies.

  ## Examples

      iex> ExCoinbase.build_product_id("BTC", "USD")
      "BTC-USD"
  """
  @spec build_product_id(String.t(), String.t()) :: String.t()
  def build_product_id(base, quote_currency) do
    "#{base}-#{quote_currency}"
  end
end
