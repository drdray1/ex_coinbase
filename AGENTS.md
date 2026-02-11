# AGENTS.md

## Project Overview

ExCoinbase is an Elixir client library for the Coinbase Advanced Trade API. It provides REST API operations (accounts, orders, products, portfolios, fees) and real-time WebSocket streaming for order updates.

## Build & Test

```bash
mix deps.get          # Install dependencies
mix compile --warnings-as-errors  # Compile (no warnings allowed)
mix test              # Run all tests
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
- `ExCoinbase.Auth` — Req plugin that signs requests with ES256 JWTs
- `ExCoinbase.JWT` — JWT token generation (ES256/ECDSA P-256 via JOSE)
- `ExCoinbase.Accounts` / `Products` / `Orders` / `Portfolio` / `Fees` — Domain modules for REST endpoints
- `ExCoinbase.WebSocket` — Event structs (`UserOrderEvent`, `OrderUpdate`, `HeartbeatEvent`) and message builders
- `ExCoinbase.WebSocket.Client` — WebSockex wrapper for raw WebSocket I/O
- `ExCoinbase.WebSocket.Connection` — GenServer managing WebSocket lifecycle, JWT refresh, reconnection, and subscriber broadcasting

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
| `jose` | JWT signing (ES256) |
| `websockex` | WebSocket client |
| `decimal` | Financial precision |
| `mimic` | Test mocking |

## Testing Conventions

- **HTTP mocking**: Use `Req.Test` stubs (plug-based). See existing tests for the pattern.
- **Module mocking**: Use `Mimic` for internal modules (e.g., `WebSockex`, `ExCoinbase.JWT`). Modules to mock are registered in `test/test_helper.exs`.
- **Fixtures**: `test/support/fixtures.ex` provides `test_client/1`, sample credentials, and response data.
- **Async**: Tests use `async: true` where possible. Mimic tests that need global mocking must set the module to global mode.
- Test files mirror `lib/` structure under `test/ex_coinbase/`.

## Code Style

- Elixir standard formatting (`mix format`).
- Comprehensive `@spec` and `@type` annotations on all public functions.
- `@moduledoc` on every module. No inline comments unless logic is non-obvious.
- Private helper functions prefixed with `defp`, grouped at the bottom of modules.
