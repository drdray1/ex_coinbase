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
    {:ex_coinbase, "~> 0.1.0"}
  ]
end
```

## Authentication

ExCoinbase uses Coinbase CDP API Keys (ES256/ECDSA P-256). Create your API key at [Coinbase CDP Portal](https://portal.cdp.coinbase.com/).

You'll need:
- **API Key ID** - looks like `organizations/{org_id}/apiKeys/{key_id}`
- **EC Private Key** - PEM-encoded ECDSA P-256 key

## Quick Start

```elixir
# Create a client
client = ExCoinbase.new(
  "organizations/abc/apiKeys/123",
  File.read!("coinbase_private_key.pem")
)

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

Real-time order updates via WebSocket:

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
