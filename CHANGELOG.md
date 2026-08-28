# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/) (pre-1.0: minor bumps may break).

## [0.2.4] - 2026-08-28

### Documentation

- Prediction markets: documented that, as of 2026-08-28, Coinbase's public
  Advanced Trade API rejects Kalshi product IDs on `POST /orders`,
  `POST /orders/preview`, `GET /best_bid_ask` and `GET /product_book`
  (`Invalid product_id`) even for contracts traded through the Coinbase app.
  History, fills, positions and Kalshi-backed discovery work; the order
  helpers follow the published schema and are kept for when the endpoints open.

## [0.2.3] - 2026-08-28

### Fixed

- `Orders.preview_order/2` (and every `Predictions.preview_*`) sent
  `client_order_id`, which `POST /orders/preview` rejects with
  `proto: unknown field "client_order_id"` — previews have failed with a
  400 since 0.1.x. It is no longer sent.
- API error tuples now carry Coinbase's `error_details`/`message` instead of
  the bare `"unknown"` code, e.g. `{:api_error, 400, "proto: unknown field ..."}`.

## [0.2.2] - 2026-08-27

Verified live: Coinbase's product endpoints cannot enumerate prediction
markets (`product_type=PREDICTION_MARKET` is a 500, `GET /products/{id}` is 404).

### Added

- `ExCoinbase.Predictions.Kalshi` — public Kalshi catalogue client
  (`list_markets/1`, `get_market/2`, `list_events/1`, `list_series/1`,
  `to_product_id/1`, `from_product_id/1`); config keys `kalshi_url`,
  `kalshi_req_options`.
- `Predictions.scan_coinbase_catalogue/2` (the old catalogue scan, kept in
  case Coinbase starts listing prediction products).

### Changed (breaking for 0.2.1 callers)

- `Predictions.list_markets/2` now reads Kalshi's catalogue and returns
  `{:ok, markets, cursor}`; each market carries `"product_id"` (`<ticker>-KALSHI`).
  Options: `series_ticker`, `event_ticker`, `tickers`, `status` (default open),
  `limit`, `cursor`, `kalshi_client`.
- `Predictions.get_market/3` fetches from Kalshi (Coinbase returns 404).

## [0.2.1] - 2026-08-27

Prediction markets verified against a live account.

### Changed

- `ExCoinbase.Predictions` market orders now use `market_market_fok` (what
  the Coinbase app sends for event contracts) instead of `market_market_ioc`.
- `Predictions.list_markets/2` tries `product_type: "PREDICTION_MARKET"` first,
  then falls back to paging `get_all_products: true` through `cursor`.
  `prediction_market?/1` also matches the `-KALSHI` product-id suffix and the
  `PREDICTION_MARKET` type; `list_orders/2` matches on `product_type` too.

### Added

- `Predictions.get_market/2`, `prediction_order?/1`, `order_product_type/0`;
  `buy_yes/buy_no` option `contracts: true` to size in contracts.

## [0.2.0] - 2026-08-26

Sync with the Coinbase Advanced Trade API as of August 2026.

### Breaking

- **Ed25519 keys**: `ExCoinbase.JWT.parse_private_key/1` now returns
  `{:error, :unsupported_private_key}` / `{:error, {:invalid_private_key, msg}}`
  instead of `{:error, :not_ec_private_key}`.
- `ExCoinbase.Orders.limit_order_ioc/5` now sends `sor_limit_ioc` — the only
  IOC limit configuration the API accepts. It previously sent `limit_limit_ioc`,
  which the API rejects.
- `ExCoinbase.Orders.list_orders/2` and `list_fills/2` take the API's real
  filter names: `product_ids`, `order_ids`, `order_types`, `order_status` (lists)
  etc. The old singular `product_id` / `order_id` / `order_type` options were
  silently ignored by the API and are no longer accepted.
- Array query parameters (`product_ids`, `order_ids`, ...) are encoded as
  repeated keys (`product_ids=A&product_ids=B`) instead of comma-joined values.
- `ExCoinbase.Client.verify_credentials/3` and `healthcheck/1` call
  `GET /key_permissions` instead of `GET /accounts`; `verify_credentials`
  returns the permissions map.

### Added

- **Ed25519 (EdDSA) API keys** — the current CDP default — accepted as the
  portal's base64 string (32- or 64-byte) or as a PKCS#8 PEM. EC P-256 (ES256)
  keys keep working; the algorithm is chosen from the key.
- **Prediction markets**: `ExCoinbase.Predictions` (`buy_yes/4`, `buy_no/4`,
  `sell_yes/4`, `sell_no/4`, `preview_yes/4`, `preview_no/4`, `create_order/6`,
  `list_markets/2`, `list_positions/2`, `list_orders/2`, extractors), plus
  `prediction_metadata` support in `Orders.create_order/2` and
  `preview_order/2`, and `Accounts.prediction_accounts/1`.
- New order fields on create/preview: `client_order_id` (caller-supplied),
  `preview_id`, `sor_preference`, `equity_order_metadata`, `cost_basis_method`.
- New order helpers: `market_order_fok/4`, `twap_order_gtd/6`, `scaled_order_gtc/5`.
- `ExCoinbase.Public` — unauthenticated `/time` and `/market/*` endpoints, with
  `ExCoinbase.Client.public/1`.
- `ExCoinbase.Convert` (`/convert/*`), `ExCoinbase.PaymentMethods`
  (`/payment_methods`), `ExCoinbase.Futures` (`/cfm/*`), `Client.key_permissions/1`.
- `Products.list_products/2` filters: `cursor`, `contract_expiry_type`,
  `expiring_contract_status`, `get_tradability_status`, `get_all_products`,
  `products_sort_order`, `futures_underlying_type`, `user_country_code`,
  `expired`; `get_candles/3` `limit`; `get_product_book/3`
  `aggregation_price_increment`; `Fees.get_transaction_summary/2` `product_venue`.
- WebSocket: `candles` and `status` market channels, `futures_balance_summary`
  user channel (`Connection` `channels:` option), `positions` on
  `UserOrderEvent`, `build_authenticated_subscribe/4`.
- `ExCoinbase.Query` shared query-string builder.
- `CHANGELOG.md`.

### Fixed

- The configured `:timeout` is now applied as the Req `receive_timeout`.
- `Connection.maybe_connect/1` guard that newer Elixir flagged as unreachable.
- `{"channel": "subscriptions"}` acknowledgements are parsed instead of
  reported as an unknown channel.

### Deprecated

- `retail_portfolio_id` on orders (API-side deprecation; legacy keys only).
- The `/intx/*` perpetuals endpoints were never wrapped and will not be:
  Coinbase moves international derivatives to a Deribit-powered JSON-RPC
  gateway on 2026-09-09.

## [0.1.3] - 2026-02

- Allow `decimal ~> 3.0`.
- Fix `ArithmeticError` in `retry_delay` when Req passes a non-positive attempt.

## [0.1.2] - 2026-02

- Order editing (`edit_order/3`, `edit_order_preview/3`), `preview_order/2`,
  `close_position/4`, FOK/GTD/stop-limit/bracket order helpers.
- Public market-data WebSocket (`ExCoinbase.WebSocket.MarketDataConnection`:
  level2, ticker, ticker_batch, market_trades).
- Test coverage above 90%.

## [0.1.1] - 2026-02

- `AGENTS.md`, improved test coverage, boolean-operator fix.

## [0.1.0] - 2026-02

- Initial release: accounts, products, orders, fees, portfolios, user-channel
  WebSocket streaming, CDP JWT (ES256) authentication.
