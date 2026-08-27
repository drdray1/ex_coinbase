defmodule ExCoinbase.RestFixtures do
  @moduledoc """
  Test fixtures for the public, convert, payment method and futures REST modules.
  """

  # ===========================================================================
  # Clients
  # ===========================================================================

  def public_client(stub_name) do
    ExCoinbase.Client.public(plug: {Req.Test, stub_name})
    |> Req.Request.merge_options(retry: false)
  end

  # ===========================================================================
  # Public Market Data
  # ===========================================================================

  def server_time_response do
    %{
      "iso" => "2024-01-01T00:00:00Z",
      "epochSeconds" => "1704067200",
      "epochMillis" => "1704067200000"
    }
  end

  def public_products_response do
    %{
      "products" => [
        %{"product_id" => "BTC-USD", "price" => "45000.00", "product_type" => "SPOT"},
        %{"product_id" => "ETH-USD", "price" => "2500.00", "product_type" => "SPOT"}
      ],
      "num_products" => 2
    }
  end

  def public_product_response do
    %{
      "product_id" => "BTC-USD",
      "price" => "45000.00",
      "product_type" => "SPOT",
      "status" => "online"
    }
  end

  def candles_response do
    %{
      "candles" => [
        %{
          "start" => "1700000000",
          "low" => "44000.00",
          "high" => "46000.00",
          "open" => "45000.00",
          "close" => "45500.00",
          "volume" => "12.5"
        }
      ]
    }
  end

  def market_trades_response do
    %{
      "trades" => [
        %{
          "trade_id" => "t-1",
          "product_id" => "BTC-USD",
          "price" => "45000.00",
          "size" => "0.1",
          "side" => "BUY"
        }
      ],
      "best_bid" => "44999.00",
      "best_ask" => "45001.00"
    }
  end

  def product_book_response do
    %{
      "pricebook" => %{
        "product_id" => "BTC-USD",
        "bids" => [%{"price" => "44999.00", "size" => "1.0"}],
        "asks" => [%{"price" => "45001.00", "size" => "0.5"}],
        "time" => "2024-01-01T00:00:00Z"
      }
    }
  end

  # ===========================================================================
  # Convert
  # ===========================================================================

  def convert_trade_response(status \\ "TRADE_STATUS_CREATED") do
    %{
      "trade" => %{
        "id" => "trade-id-123",
        "status" => status,
        "user_entered_amount" => %{"value" => "100.00", "currency" => "USD"},
        "amount" => %{"value" => "100.00", "currency" => "USD"},
        "source_currency" => "USD",
        "target_currency" => "USDC"
      }
    }
  end

  # ===========================================================================
  # Payment Methods
  # ===========================================================================

  def payment_methods_response do
    %{
      "payment_methods" => [
        %{
          "id" => "pm-1",
          "type" => "ACH",
          "name" => "Checking",
          "currency" => "USD",
          "verified" => true
        },
        %{
          "id" => "pm-2",
          "type" => "COINBASE_FIAT_ACCOUNT",
          "name" => "USD Wallet",
          "currency" => "USD"
        }
      ]
    }
  end

  def payment_method_response do
    %{
      "payment_method" => %{
        "id" => "pm-1",
        "type" => "ACH",
        "name" => "Checking",
        "currency" => "USD",
        "verified" => true
      }
    }
  end

  # ===========================================================================
  # Futures
  # ===========================================================================

  def balance_summary_response do
    %{
      "balance_summary" => %{
        "futures_buying_power" => %{"value" => "5000.00", "currency" => "USD"},
        "total_usd_balance" => %{"value" => "10000.00", "currency" => "USD"},
        "cbi_usd_balance" => %{"value" => "5000.00", "currency" => "USD"},
        "cfm_usd_balance" => %{"value" => "5000.00", "currency" => "USD"},
        "unrealized_pnl" => %{"value" => "120.00", "currency" => "USD"}
      }
    }
  end

  def positions_response do
    %{
      "positions" => [
        %{
          "product_id" => "BIT-28FEB25-CDE",
          "expiration_time" => "2025-02-28T16:00:00Z",
          "side" => "LONG",
          "number_of_contracts" => "2",
          "current_price" => "45000.00",
          "unrealized_pnl" => "120.00"
        }
      ]
    }
  end

  def position_response do
    %{
      "position" => %{
        "product_id" => "BIT-28FEB25-CDE",
        "side" => "LONG",
        "number_of_contracts" => "2"
      }
    }
  end

  def sweeps_response do
    %{
      "sweeps" => [
        %{
          "id" => "sweep-1",
          "requested_amount" => %{"value" => "100.00", "currency" => "USD"},
          "should_sweep_all" => false,
          "status" => "PENDING",
          "scheduled_time" => "2024-01-01T00:00:00Z"
        }
      ]
    }
  end

  def margin_setting_response do
    %{"setting" => "INTRADAY_MARGIN_SETTING_STANDARD"}
  end

  def margin_window_response do
    %{
      "margin_window" => %{
        "margin_window_type" => "FCM_MARGIN_WINDOW_TYPE_INTRADAY",
        "end_time" => "2024-01-01T16:00:00Z"
      },
      "is_intraday_margin_killswitch_enabled" => false,
      "is_intraday_margin_enrollment_killswitch_enabled" => false
    }
  end
end
