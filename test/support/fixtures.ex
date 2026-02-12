defmodule ExCoinbase.Fixtures do
  @moduledoc """
  Test fixtures for ExCoinbase API testing.
  """

  # ===========================================================================
  # Credentials
  # ===========================================================================

  def sample_api_key do
    "organizations/test-org-id/apiKeys/test-api-key-id"
  end

  def sample_private_key_pem do
    """
    -----BEGIN EC PRIVATE KEY-----
    MHQCAQEEIBkg8SHVK+FtTyXQK/gA1wvBGgXNIRmL+zFCPHpYk1YqoAcGBSuBBAAK
    oUQDQgAEz9hWQOFpNFkANwzJ+Lkl1+QZGEfPc0gKWPkWWlSVZSx5O7hVr0d8u+5s
    e0YqGS1PcFzALhwDHHkxnAhPk4jNvQ==
    -----END EC PRIVATE KEY-----
    """
  end

  def invalid_pem do
    "not a valid PEM format"
  end

  # ===========================================================================
  # Account Responses
  # ===========================================================================

  def sample_accounts_response do
    %{
      "accounts" => [
        %{
          "uuid" => "test-account-uuid",
          "name" => "Test Account",
          "currency" => "USD",
          "available_balance" => %{
            "value" => "10000.00",
            "currency" => "USD"
          },
          "default" => true,
          "active" => true,
          "created_at" => "2024-01-01T00:00:00Z",
          "updated_at" => "2024-01-01T00:00:00Z",
          "type" => "ACCOUNT_TYPE_FIAT"
        },
        %{
          "uuid" => "btc-account-uuid",
          "name" => "BTC Wallet",
          "currency" => "BTC",
          "available_balance" => %{
            "value" => "1.5",
            "currency" => "BTC"
          },
          "default" => false,
          "active" => true,
          "created_at" => "2024-01-01T00:00:00Z",
          "updated_at" => "2024-01-01T00:00:00Z",
          "type" => "ACCOUNT_TYPE_CRYPTO"
        }
      ],
      "has_next" => false,
      "cursor" => ""
    }
  end

  def sample_account_response do
    %{
      "account" => %{
        "uuid" => "test-account-uuid",
        "name" => "Test Account",
        "currency" => "USD",
        "available_balance" => %{
          "value" => "10000.00",
          "currency" => "USD"
        }
      }
    }
  end

  # ===========================================================================
  # Order Responses
  # ===========================================================================

  def sample_create_order_response do
    %{
      "success" => true,
      "success_response" => %{
        "order_id" => "new-order-id",
        "product_id" => "BTC-USD",
        "side" => "BUY",
        "client_order_id" => "client-123"
      }
    }
  end

  def sample_orders_response do
    %{
      "orders" => [
        %{
          "order_id" => "order-1",
          "product_id" => "BTC-USD",
          "side" => "BUY",
          "status" => "OPEN"
        },
        %{
          "order_id" => "order-2",
          "product_id" => "ETH-USD",
          "side" => "SELL",
          "status" => "FILLED"
        }
      ]
    }
  end

  def sample_fills_response do
    %{
      "fills" => [
        %{
          "fill_id" => "fill-1",
          "order_id" => "order-1",
          "product_id" => "BTC-USD",
          "price" => "50000.00",
          "size" => "0.1",
          "commission" => "5.00"
        }
      ]
    }
  end

  def sample_cancel_orders_response do
    %{
      "results" => [
        %{"success" => true, "order_id" => "order-1"},
        %{"success" => true, "order_id" => "order-2"}
      ]
    }
  end

  # ===========================================================================
  # Product Responses
  # ===========================================================================

  def sample_products_response do
    %{
      "products" => [
        %{
          "product_id" => "BTC-USD",
          "base_currency_id" => "BTC",
          "quote_currency_id" => "USD",
          "base_increment" => "0.00000001",
          "quote_increment" => "0.01",
          "price" => "50000.00",
          "status" => "online"
        },
        %{
          "product_id" => "ETH-USD",
          "base_currency_id" => "ETH",
          "quote_currency_id" => "USD",
          "base_increment" => "0.0001",
          "quote_increment" => "0.01",
          "price" => "3000.00",
          "status" => "online"
        }
      ]
    }
  end

  def sample_candles_response do
    %{
      "candles" => [
        %{
          "start" => "1704067200",
          "open" => "50000.00",
          "high" => "50500.00",
          "low" => "49500.00",
          "close" => "50200.00",
          "volume" => "100.5"
        },
        %{
          "start" => "1704070800",
          "open" => "50200.00",
          "high" => "50800.00",
          "low" => "50100.00",
          "close" => "50600.00",
          "volume" => "85.2"
        }
      ]
    }
  end

  # ===========================================================================
  # Portfolio Responses
  # ===========================================================================

  def sample_portfolios_response do
    %{
      "portfolios" => [
        %{
          "uuid" => "default-portfolio-uuid",
          "name" => "Default",
          "type" => "DEFAULT",
          "deleted" => false
        },
        %{
          "uuid" => "trading-portfolio-uuid",
          "name" => "Trading Portfolio",
          "type" => "CONSUMER",
          "deleted" => false
        }
      ]
    }
  end

  def sample_portfolio_breakdown_response do
    %{
      "breakdown" => %{
        "portfolio" => %{
          "uuid" => "portfolio-uuid",
          "name" => "Default",
          "type" => "DEFAULT"
        },
        "portfolio_balances" => %{
          "total_balance" => %{"value" => "15000.00", "currency" => "USD"},
          "total_cash_equivalent_balance" => %{"value" => "10000.00", "currency" => "USD"}
        },
        "spot_positions" => [
          %{
            "asset" => "BTC",
            "account_uuid" => "btc-account-uuid",
            "total_balance_fiat" => "5000.00",
            "total_balance_crypto" => "0.1"
          }
        ]
      }
    }
  end

  # ===========================================================================
  # Fee/Transaction Summary Responses
  # ===========================================================================

  def sample_transaction_summary_response do
    %{
      "total_volume" => 50_000.0,
      "total_fees" => 125.5,
      "fee_tier" => %{
        "pricing_tier" => "Advanced",
        "maker_fee_rate" => "0.004",
        "taker_fee_rate" => "0.006",
        "usd_from" => "0",
        "usd_to" => "10000"
      },
      "margin_rate" => nil,
      "advanced_trade_only_volume" => 45_000.0,
      "advanced_trade_only_fees" => 120.0
    }
  end

  def sample_transaction_summary_string_response do
    %{
      "total_volume" => "50000.00",
      "total_fees" => "125.50",
      "fee_tier" => %{
        "pricing_tier" => "Advanced",
        "maker_fee_rate" => "0.004",
        "taker_fee_rate" => "0.006"
      }
    }
  end

  # ===========================================================================
  # WebSocket Event Fixtures
  # ===========================================================================

  def sample_heartbeat_event do
    %{
      "channel" => "heartbeats",
      "client_id" => "",
      "timestamp" => "2024-01-01T00:00:00.000000Z",
      "sequence_num" => 1,
      "events" => [
        %{
          "current_time" => "2024-01-01T00:00:00.000Z",
          "heartbeat_counter" => 1
        }
      ]
    }
  end

  def sample_user_event do
    %{
      "channel" => "user",
      "client_id" => "",
      "timestamp" => "2024-01-01T00:00:00.000000Z",
      "sequence_num" => 400,
      "events" => [
        %{
          "type" => "snapshot",
          "orders" => [
            %{
              "order_id" => "order-123",
              "product_id" => "BTC-USD",
              "side" => "BUY",
              "status" => "OPEN",
              "order_type" => "LIMIT"
            }
          ]
        }
      ]
    }
  end

  def sample_error_event do
    %{
      "type" => "error",
      "message" => "Invalid product ID"
    }
  end

  def sample_subscriptions_event do
    %{
      "type" => "subscriptions",
      "channel" => "subscriptions",
      "events" => [
        %{
          "subscriptions" => %{
            "ticker" => ["BTC-USD", "ETH-USD"]
          }
        }
      ]
    }
  end

  # ===========================================================================
  # Order Edit/Preview/Close Responses
  # ===========================================================================

  def sample_edit_order_response do
    %{
      "success" => true,
      "errors" => [],
      "order" => %{
        "order_id" => "order-123",
        "product_id" => "BTC-USD",
        "side" => "BUY",
        "status" => "PENDING"
      }
    }
  end

  def sample_edit_order_preview_response do
    %{
      "slippage" => "0.01",
      "order_total" => "51.00",
      "commission_total" => "0.30",
      "quote_size" => "51.00",
      "base_size" => "0.001",
      "best_bid" => "50999.00",
      "best_ask" => "51001.00",
      "average_filled_price" => "51000.00"
    }
  end

  def sample_preview_order_response do
    %{
      "order_total" => "100.60",
      "commission_total" => "0.60",
      "errs" => [],
      "warning" => [],
      "quote_size" => "100.00",
      "base_size" => "0.002",
      "best_bid" => "49999.00",
      "best_ask" => "50001.00",
      "is_max" => false,
      "order_margin_total" => "0",
      "leverage" => "1",
      "slippage" => "0.02"
    }
  end

  def sample_close_position_response do
    %{
      "success" => true,
      "success_response" => %{
        "order_id" => "close-order-id",
        "product_id" => "BTC-USD",
        "side" => "SELL",
        "client_order_id" => "close-order-123"
      }
    }
  end

  # ===========================================================================
  # Market Data WebSocket Event Fixtures
  # ===========================================================================

  def sample_level2_event do
    %{
      "channel" => "l2_data",
      "client_id" => "",
      "timestamp" => "2024-01-01T00:00:00.000000Z",
      "sequence_num" => 1,
      "events" => [
        %{
          "type" => "snapshot",
          "product_id" => "BTC-USD",
          "updates" => [
            %{"side" => "bid", "price_level" => "49999.00", "new_quantity" => "1.5"},
            %{"side" => "offer", "price_level" => "50001.00", "new_quantity" => "2.0"}
          ]
        }
      ]
    }
  end

  def sample_ticker_event do
    %{
      "channel" => "ticker",
      "client_id" => "",
      "timestamp" => "2024-01-01T00:00:00.000000Z",
      "sequence_num" => 5,
      "events" => [
        %{
          "type" => "snapshot",
          "tickers" => [
            %{
              "type" => "ticker",
              "product_id" => "BTC-USD",
              "price" => "50000.00",
              "volume_24_h" => "12345.67",
              "low_24_h" => "49000.00",
              "high_24_h" => "51000.00",
              "low_52_w" => "30000.00",
              "high_52_w" => "69000.00",
              "price_percent_chg_24_h" => "2.5"
            }
          ]
        }
      ]
    }
  end

  def sample_ticker_batch_event do
    %{
      "channel" => "ticker_batch",
      "client_id" => "",
      "timestamp" => "2024-01-01T00:00:00.000000Z",
      "sequence_num" => 10,
      "events" => [
        %{
          "type" => "snapshot",
          "tickers" => [
            %{"product_id" => "BTC-USD", "price" => "50000.00"},
            %{"product_id" => "ETH-USD", "price" => "3000.00"}
          ]
        }
      ]
    }
  end

  def sample_market_trades_ws_event do
    %{
      "channel" => "market_trades",
      "client_id" => "",
      "timestamp" => "2024-01-01T00:00:00.000000Z",
      "sequence_num" => 20,
      "events" => [
        %{
          "type" => "snapshot",
          "trades" => [
            %{
              "trade_id" => "trade-1",
              "product_id" => "BTC-USD",
              "price" => "50000.00",
              "size" => "0.01",
              "side" => "BUY",
              "time" => "2024-01-01T00:00:00Z"
            }
          ]
        }
      ]
    }
  end

  # ===========================================================================
  # Test Client Factory
  # ===========================================================================

  # P-256 key required for JWT ES256 signing (used in HTTP integration tests)
  def sample_p256_private_key_pem do
    """
    -----BEGIN EC PRIVATE KEY-----
    MHcCAQEEIJu/Ze6KwFX6kqjf0YTCwuFtFwcaIA6NfRc2XaioC8DdoAoGCCqGSM49
    AwEHoUQDQgAE6ob5+ow9MXBF4R28xeIzj5djEWB9OM681bQ2IlqjV4LJAKdRyPRX
    7cjqMZo/TspePuKrd936h3l17oeU4qlgHw==
    -----END EC PRIVATE KEY-----
    """
  end

  def test_client(stub_name) do
    sample_api_key()
    |> ExCoinbase.Client.new(
      sample_p256_private_key_pem(),
      plug: {Req.Test, stub_name}
    )
    |> Req.Request.merge_options(retry: false)
  end

  # ===========================================================================
  # Additional API Response Fixtures
  # ===========================================================================

  def sample_market_trades_response do
    %{
      "trades" => [
        %{
          "trade_id" => "trade-1",
          "product_id" => "BTC-USD",
          "price" => "50000.00",
          "size" => "0.1",
          "time" => "2024-01-01T00:00:00Z",
          "side" => "BUY"
        }
      ],
      "best_bid" => "49999.00",
      "best_ask" => "50001.00"
    }
  end

  def sample_best_bid_ask_response do
    %{
      "pricebooks" => [
        %{
          "product_id" => "BTC-USD",
          "bids" => [%{"price" => "49999.00", "size" => "1.0"}],
          "asks" => [%{"price" => "50001.00", "size" => "1.0"}]
        }
      ]
    }
  end

  def sample_product_book_response do
    %{
      "pricebook" => %{
        "product_id" => "BTC-USD",
        "bids" => [%{"price" => "49999.00", "size" => "1.0"}],
        "asks" => [%{"price" => "50001.00", "size" => "1.0"}]
      }
    }
  end

  def sample_single_order_response do
    %{
      "order" => %{
        "order_id" => "order-1",
        "product_id" => "BTC-USD",
        "side" => "BUY",
        "status" => "FILLED"
      }
    }
  end

  def sample_portfolio_response do
    %{
      "portfolio" => %{
        "uuid" => "portfolio-uuid",
        "name" => "Trading Portfolio",
        "type" => "CONSUMER"
      }
    }
  end

  def sample_move_funds_response do
    %{
      "source_portfolio_uuid" => "source-uuid",
      "target_portfolio_uuid" => "target-uuid"
    }
  end
end
