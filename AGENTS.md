# AGENTS.md

## Project Overview

ExCoinbase is an Elixir client library for the Coinbase Advanced Trade API. It provides REST API operations (accounts, orders, prediction markets, products, portfolios, fees, US futures, convert, payment methods, public market data) and real-time WebSocket streaming (user orders/positions, futures balances, public market data).

## Build & Test

```bash
mix deps.get          # Install dependencies
mix compile --warnings-as-errors  # Compile (no warnings allowed)
mix test              # Run all tests
mix test --cover      # Coverage report; fails if total < 90% (per-module target is also 90%)
mix test test/ex_coinbase/orders_test.exs          # Run a single test file
mix test test/ex_coinbase/orders_test.exs:42        # Run a specific test (line number)
mix credo             # Lint / static analysis
mix format            # Format code
mix format --check-formatted  # Check formatting without changes
```

## Architecture

### Module Structure

- `ExCoinbase` — Public API facade; delegates to domain modules
- `ExCoinbase.Client` — HTTP client built on `Req`; handles base URLs, retries, response parsing
- `ExCoinbase.Auth` — Req plugin that signs requests with CDP JWTs
- `ExCoinbase.JWT` — JWT generation; picks `EdDSA` (Ed25519, base64 or PKCS#8 PEM) or `ES256` (EC P-256 PEM) from the key
- `ExCoinbase.Query` — Query-string builder (whitelist, drop nils, lists → repeated keys). Always use `Query.url/3`, never Req's `params:` (it encodes lists as `key[]=`, which the API rejects)
- `ExCoinbase.Accounts` / `Products` / `Orders` / `Portfolio` / `Fees` / `Futures` / `Convert` / `PaymentMethods` — Domain modules for authenticated REST endpoints
- `ExCoinbase.Predictions` — Prediction-market (YES/NO event contract) wrapper over Orders/Products/Portfolio
- `ExCoinbase.Public` — Unauthenticated `/time` + `/market/*` endpoints (client from `Client.public/1`)
- `ExCoinbase.WebSocket` — Event structs and message builders/parsers for every channel
- `ExCoinbase.WebSocket.Client` — WebSockex wrapper for raw WebSocket I/O
- `ExCoinbase.WebSocket.Connection` — GenServer for the authenticated user stream (`user`, `futures_balance_summary`): JWT refresh, reconnection, subscriber broadcasting
- `ExCoinbase.WebSocket.MarketDataConnection` — GenServer for the public market-data stream (`level2`, `ticker`, `ticker_batch`, `market_trades`, `candles`, `status`)

### API reference

Spec files worth re-checking when the API drifts: OpenAPI `https://docs.cdp.coinbase.com/api-reference/advanced-trade-api/rest-api/advanced-trade-spec.yaml`, AsyncAPI `https://docs.cdp.coinbase.com/api-reference/advanced-trade-api/advanced-trade-asyncapi.json`. Array query params are `explode: true` (repeated keys). `/intx/*` is deprecated (Deribit JSON-RPC gateway from 2026-09-09) and intentionally not wrapped.

### Key Patterns

- **Delegation**: `ExCoinbase` delegates all public functions to domain modules — add new public API functions there, not in the facade directly.
- **Req plugin auth**: `ExCoinbase.Auth` attaches as a Req request step. JWT is generated per-request.
- **Result tuples**: All API functions return `{:ok, data}` or `{:error, reason}`. Error atoms: `:unauthorized`, `:forbidden`, `:not_found`, `:rate_limited`, `:unknown`.
- **GenServer for WebSocket**: `Connection` manages state, timers (reconnect with exponential backoff 1s–30s, JWT refresh at 100s intervals), and multi-subscriber support.

### Dependencies

| Dependency | Purpose |
|-----------|---------|
| `req` | HTTP client |
| `jason` | JSON codec |
| `jose` | JWT signing (EdDSA / ES256) |
| `websockex` | WebSocket client |
| `decimal` | Financial precision |
| `mimic` | Test mocking |

## Testing Conventions

- **HTTP mocking**: Use `Req.Test` stubs (plug-based). See existing tests for the pattern.
- **Module mocking**: Use `Mimic` for internal modules (e.g., `WebSockex`, `ExCoinbase.JWT`). Modules to mock are registered in `test/test_helper.exs`.
- **Fixtures**: `test/support/fixtures.ex` provides `test_client/1`, sample credentials (EC and Ed25519), and response data; `test/support/rest_fixtures.ex` has payloads for the newer REST modules and `public_client/1`.
- Assert exact `conn.query_string` values in endpoint tests so repeated-key encoding stays correct.
- **Async**: Tests use `async: true` where possible. Mimic tests that need global mocking must set the module to global mode.
- Test files mirror `lib/` structure under `test/ex_coinbase/`.

## Code Style

- Elixir standard formatting (`mix format`).
- Comprehensive `@spec` and `@type` annotations on all public functions.
- `@moduledoc` on every module. No inline comments unless logic is non-obvious.
- Private helper functions prefixed with `defp`, grouped at the bottom of modules.
