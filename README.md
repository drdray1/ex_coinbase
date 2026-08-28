# ExCoinbase

[![Hex.pm](https://img.shields.io/hexpm/v/ex_coinbase.svg)](https://hex.pm/packages/ex_coinbase)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/ex_coinbase)

Elixir client for the [Coinbase Advanced Trade API](https://docs.cdp.coinbase.com/advanced-trade/docs/welcome).

Supports REST endpoints for accounts, products, orders, fees, and portfolios, plus real-time WebSocket streaming for order updates.

## Installation

Add `ex_coinbase` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_coinbase, "~> 0.2.2"}
  ]
end
```

## Authentication

ExCoinbase uses Coinbase CDP Secret API Keys. Create one at the [Coinbase CDP Portal](https://portal.cdp.coinbase.com/).

You'll need:
- **API Key ID** - looks like `organizations/{org_id}/apiKeys/{key_id}`
- **Private Key** - either
  - the **Ed25519** secret the portal shows for new keys (a base64 string such as
    `"IY0DiD66…59c="`; signed with `EdDSA`), or
  - a PEM-encoded key — Ed25519 PKCS#8 (`-----BEGIN PRIVATE KEY-----`) or the
    legacy ECDSA P-256 (`-----BEGIN EC PRIVATE KEY-----`; signed with `ES256`).

The signing algorithm is chosen automatically from the key.

## Quick Start

```elixir
# Create a client (base64 Ed25519 secret or PEM both work)
client = ExCoinbase.new(
  "organizations/abc/apiKeys/123",
  System.fetch_env!("COINBASE_API_SECRET")
)

# Check what the key can do
{:ok, %{"can_trade" => true}} = ExCoinbase.key_permissions(client)

# List accounts
{:ok, response} = ExCoinbase.list_accounts(client)
accounts = ExCoinbase.extract_accounts(response)

# Get market data
{:ok, response} = ExCoinbase.get_candles(client, "BTC-USD",
  start: "2024-01-01T00:00:00Z",
  end: "2024-01-02T00:00:00Z",
  granularity: "ONE_HOUR"
)
candles = ExCoinbase.extract_candles(response)

# Place a market order (buy $100 of BTC)
{:ok, response} = ExCoinbase.market_order_quote(client, "BTC-USD", "BUY", "100")

# Place a limit order
{:ok, response} = ExCoinbase.limit_order_gtc(client, "BTC-USD", "BUY", "0.001", "50000.00")

# Check fees
{:ok, summary} = ExCoinbase.get_transaction_summary(client)
maker_rate = ExCoinbase.maker_fee_rate(summary)
taker_rate = ExCoinbase.taker_fee_rate(summary)
```

## REST API

### Accounts

```elixir
{:ok, response} = ExCoinbase.list_accounts(client)
{:ok, response} = ExCoinbase.list_accounts(client, limit: 50, cursor: "next_cursor")
{:ok, response} = ExCoinbase.get_account(client, "account-uuid")
```

### Products & Market Data

```elixir
{:ok, response} = ExCoinbase.list_products(client)
{:ok, response} = ExCoinbase.list_products(client, product_type: "SPOT")
{:ok, response} = ExCoinbase.get_product(client, "BTC-USD")

{:ok, response} = ExCoinbase.get_candles(client, "BTC-USD",
  start: "2024-01-01T00:00:00Z",
  end: "2024-01-02T00:00:00Z",
  granularity: "ONE_HOUR"
)

{:ok, response} = ExCoinbase.get_best_bid_ask(client, ["BTC-USD", "ETH-USD"])
{:ok, response} = ExCoinbase.get_market_trades(client, "BTC-USD", limit: 100)
```

### Orders

```elixir
# Market orders
{:ok, resp} = ExCoinbase.market_order_quote(client, "BTC-USD", "BUY", "100")
{:ok, resp} = ExCoinbase.market_order_base(client, "BTC-USD", "BUY", "0.001")

# Limit orders
{:ok, resp} = ExCoinbase.limit_order_gtc(client, "BTC-USD", "BUY", "0.001", "50000.00")

# Stop-limit orders
{:ok, resp} = ExCoinbase.stop_limit_order_gtc(
  client, "BTC-USD", "SELL", "0.001", "45000.00", "44000.00"
)

# Bracket orders (entry + take-profit + stop-loss)
{:ok, resp} = ExCoinbase.bracket_order_gtc(
  client, "BTC-USD", "BUY", "0.001",
  "50000.00",  # entry price
  "55000.00",  # take profit
  "48000.00"   # stop loss
)

# Order management
{:ok, orders} = ExCoinbase.list_orders(client, product_id: "BTC-USD", order_status: ["OPEN"])
{:ok, order} = ExCoinbase.get_order(client, "order-id")
{:ok, resp} = ExCoinbase.cancel_order(client, "order-id")
{:ok, fills} = ExCoinbase.list_fills(client, product_id: "BTC-USD")
```

### Prediction Markets

Kalshi event contracts trade through the normal order endpoints with a YES/NO
`prediction_metadata`. Product IDs are Kalshi tickers with a `-KALSHI` suffix
(e.g. `KXBTC15M-26AUG270830-30-KALSHI`). Contracts price between 0 and 1 USD;
`base_size` is a number of contracts, `quote_size` is USD; market orders are
fill-or-kill. NO is a short on the YES book — the API handles that when you
pass the side.

Coinbase's own product endpoints cannot list prediction markets, so discovery
goes through Kalshi's public catalogue (no key needed) via
`ExCoinbase.Predictions.Kalshi`; product IDs are `<kalshi ticker>-KALSHI`.

```elixir
# Discover open BTC 15-minute markets
{:ok, markets, _cursor} = ExCoinbase.list_markets(client, series_ticker: "KXBTC15M")
%{"product_id" => product_id, "yes_ask_dollars" => yes_ask} = hd(markets)
{:ok, market} = ExCoinbase.get_market(client, product_id)

# Preview: how many YES contracts does $10 buy after slippage?
{:ok, preview} = ExCoinbase.preview_yes(client, product_id, "10")
ExCoinbase.extract_prediction_metadata(preview)["minimum_contracts"]

# Buy $10 of YES at market; buy 20 NO contracts at a 0.35 limit
{:ok, _} = ExCoinbase.buy_yes(client, product_id, "10")
{:ok, _} = ExCoinbase.buy_no(client, product_id, "20", limit_price: "0.35")

# Sell 5 YES contracts at market
{:ok, _} = ExCoinbase.sell_yes(client, product_id, "5")

# Positions and orders
{:ok, positions} = ExCoinbase.list_prediction_positions(client, portfolio_uuid)
{:ok, orders} = ExCoinbase.list_prediction_orders(client, order_status: ["OPEN"])
```

Lower-level: `ExCoinbase.Orders.create_order/2` accepts
`prediction_metadata: %{prediction_side: "PREDICTION_SIDE_YES" | "PREDICTION_SIDE_NO"}`
with any order configuration.

### Public Market Data (no API key)

```elixir
public = ExCoinbase.public()
{:ok, %{"iso" => _}} = ExCoinbase.server_time(public)
{:ok, product} = ExCoinbase.public_get_product(public, "BTC-USD")
{:ok, book} = ExCoinbase.public_get_product_book(public, "BTC-USD", limit: 10)
```

### US Futures, Convert, Payment Methods

```elixir
{:ok, summary} = ExCoinbase.futures_balance_summary(client)
{:ok, positions} = ExCoinbase.list_futures_positions(client)
{:ok, _} = ExCoinbase.set_intraday_margin_setting(client, "INTRADAY_MARGIN_SETTING_INTRADAY")

{:ok, quote} = ExCoinbase.create_convert_quote(client, usd_account, usdc_account, "100")
{:ok, _} = ExCoinbase.commit_convert_trade(client, quote["trade"]["id"], usd_account, usdc_account)

{:ok, methods} = ExCoinbase.list_payment_methods(client)
```

### Portfolios

```elixir
{:ok, response} = ExCoinbase.list_portfolios(client)
{:ok, response} = ExCoinbase.create_portfolio(client, "Trading Portfolio")
{:ok, response} = ExCoinbase.get_portfolio_breakdown(client, "portfolio-uuid")
{:ok, response} = ExCoinbase.move_funds(client, %{
  source_portfolio_uuid: "source-uuid",
  target_portfolio_uuid: "target-uuid",
  funds: %{value: "100.00", currency: "USD"}
})
```

### Fees

```elixir
{:ok, summary} = ExCoinbase.get_transaction_summary(client)
maker_rate = ExCoinbase.maker_fee_rate(summary)
taker_rate = ExCoinbase.taker_fee_rate(summary)
estimated = ExCoinbase.estimate_fee(summary, Decimal.new("1000"), true)
```

## WebSocket Streaming

Authenticated user stream (`user` orders/positions and, optionally, `futures_balance_summary`):

```elixir
{:ok, pid} = ExCoinbase.WebSocket.Connection.start_link(
  api_key_id: "organizations/abc/apiKeys/123",
  private_key_pem: File.read!("coinbase_private_key.pem")
)

# Subscribe to order updates
ExCoinbase.WebSocket.Connection.add_subscriber(pid, self())
ExCoinbase.WebSocket.Connection.subscribe(pid, ["BTC-USD", "ETH-USD"])

# Receive events in your process
receive do
  {:coinbase_user_event, %ExCoinbase.WebSocket.UserOrderEvent{} = event} ->
    IO.inspect(event.events, label: "order updates")

  {:coinbase_heartbeat, %ExCoinbase.WebSocket.HeartbeatEvent{}} ->
    :ok
end

# Futures balances need no products: start with channels: [:user, :futures_balance_summary]
# and receive {:coinbase_futures_balance_event, %ExCoinbase.WebSocket.FuturesBalanceSummaryEvent{}}
```

Public market data (no key) — `level2`, `ticker`, `ticker_batch`, `market_trades`, `candles`, `status`:

```elixir
{:ok, pid} = ExCoinbase.WebSocket.MarketDataConnection.start_link()
ExCoinbase.WebSocket.MarketDataConnection.add_subscriber(pid, self())
ExCoinbase.WebSocket.MarketDataConnection.subscribe(pid, "ticker", ["BTC-USD"])
ExCoinbase.WebSocket.MarketDataConnection.subscribe(pid, "candles", ["BTC-USD"])

receive do
  {:coinbase_market_event, :ticker, %ExCoinbase.WebSocket.TickerEvent{tickers: tickers}} -> tickers
  {:coinbase_market_event, :candles, %ExCoinbase.WebSocket.CandlesEvent{candles: candles}} -> candles
end
```

## Configuration

All configuration is optional with sensible defaults:

```elixir
# config/config.exs
config :ex_coinbase,
  config: [
    base_url: "https://api.coinbase.com/api/v3/brokerage",
    sandbox_url: "https://api-sandbox.coinbase.com/api/v3/brokerage",
    websocket_url: "wss://advanced-trade-ws.coinbase.com",
    websocket_user_url: "wss://advanced-trade-ws-user.coinbase.com",
    timeout: 30_000
  ]
```

### Sandbox Mode

Use the sandbox environment for testing:

```elixir
client = ExCoinbase.new(api_key, private_key, sandbox: true)
```

## Testing

ExCoinbase uses [Req](https://hexdocs.pm/req) as its HTTP client, which makes testing straightforward with `Req.Test`:

```elixir
# In your test
client = ExCoinbase.Client.new(api_key, pem, plug: {Req.Test, MyApp.Coinbase})

Req.Test.stub(MyApp.Coinbase, fn conn ->
  case conn.request_path do
    "/api/v3/brokerage/accounts" ->
      Req.Test.json(conn, %{"accounts" => [%{"uuid" => "test-123"}]})

    "/api/v3/brokerage/orders" ->
      Req.Test.json(conn, %{"success" => true, "success_response" => %{"order_id" => "ord-1"}})
  end
end)
```

## License

MIT License. See [LICENSE](LICENSE) for details.
