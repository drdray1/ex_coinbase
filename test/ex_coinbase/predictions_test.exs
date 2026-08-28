defmodule ExCoinbase.PredictionsTest do
  use ExUnit.Case, async: true

  alias ExCoinbase.Fixtures
  alias ExCoinbase.Predictions
  alias ExCoinbase.Predictions.Kalshi

  @stub_name ExCoinbase.PredictionsTest
  @product "KXBTC-26SEP30-100K-KALSHI"

  defp expect_order(path, assertions) do
    Req.Test.expect(@stub_name, fn conn ->
      assert conn.request_path == "/api/v3/brokerage#{path}"
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assertions.(Jason.decode!(body))
      Req.Test.json(conn, Fixtures.sample_create_order_response())
    end)

    Fixtures.test_client(@stub_name)
  end

  describe "buy/sell helpers" do
    test "buy_yes places a market FOK quote-size order with YES metadata" do
      client =
        expect_order("/orders", fn body ->
          assert body["product_id"] == @product
          assert body["side"] == "BUY"
          assert body["order_configuration"] == %{"market_market_fok" => %{"quote_size" => "10"}}
          assert body["prediction_metadata"] == %{"prediction_side" => "PREDICTION_SIDE_YES"}
          assert is_binary(body["client_order_id"])
        end)

      assert {:ok, %{"success" => true}} = Predictions.buy_yes(client, @product, "10")
    end

    test "buy_no with limit_price places a limit GTC order in contracts" do
      client =
        expect_order("/orders", fn body ->
          assert body["side"] == "BUY"

          assert body["order_configuration"] == %{
                   "limit_limit_gtc" => %{"base_size" => "20", "limit_price" => "0.35"}
                 }

          assert body["prediction_metadata"]["prediction_side"] == "PREDICTION_SIDE_NO"
          assert body["client_order_id"] == "cid-1"
        end)

      assert {:ok, _} =
               Predictions.buy_no(client, @product, "20",
                 limit_price: "0.35",
                 client_order_id: "cid-1"
               )
    end

    test "buy_yes with contracts: true sizes in contracts" do
      client =
        expect_order("/orders", fn body ->
          assert body["order_configuration"] == %{"market_market_fok" => %{"base_size" => "7"}}
        end)

      assert {:ok, _} = Predictions.buy_yes(client, @product, "7", contracts: true)
    end

    test "sell_yes places a market FOK base-size order" do
      client =
        expect_order("/orders", fn body ->
          assert body["side"] == "SELL"
          assert body["order_configuration"] == %{"market_market_fok" => %{"base_size" => "5"}}
          assert body["prediction_metadata"]["prediction_side"] == "PREDICTION_SIDE_YES"
        end)

      assert {:ok, _} = Predictions.sell_yes(client, @product, "5")
    end

    test "sell_no forwards extra prediction metadata and preview_id" do
      client =
        expect_order("/orders", fn body ->
          assert body["prediction_metadata"] == %{
                   "prediction_side" => "PREDICTION_SIDE_NO",
                   "preview_order_est_average_filled_price" => "0.42",
                   "supports_fractional_base_size" => false
                 }

          assert body["preview_id"] == "prev-9"
        end)

      assert {:ok, _} =
               Predictions.sell_no(client, @product, "3",
                 est_average_filled_price: "0.42",
                 supports_fractional_base_size: false,
                 preview_id: "prev-9"
               )
    end

    test "create_order rejects an invalid prediction side" do
      client = Fixtures.test_client(@stub_name)

      assert {:error, {:validation_error, [msg]}} =
               Predictions.create_order(client, @product, "BUY", "MAYBE", %{
                 market_market_ioc: %{quote_size: "1"}
               })

      assert msg =~ "prediction_side"
    end

    test "create_order accepts arbitrary configurations" do
      client =
        expect_order("/orders", fn body ->
          assert body["order_configuration"] == %{
                   "limit_limit_gtd" => %{
                     "base_size" => "1",
                     "limit_price" => "0.5",
                     "end_time" => "2026-12-31T00:00:00Z"
                   }
                 }
        end)

      assert {:ok, _} =
               Predictions.create_order(client, @product, "SELL", "PREDICTION_SIDE_NO", %{
                 limit_limit_gtd: %{
                   base_size: "1",
                   limit_price: "0.5",
                   end_time: "2026-12-31T00:00:00Z"
                 }
               })
    end
  end

  describe "preview" do
    test "preview_yes hits /orders/preview and exposes prediction metadata" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.request_path == "/api/v3/brokerage/orders/preview"
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        assert Jason.decode!(body)["prediction_metadata"]["prediction_side"] ==
                 "PREDICTION_SIDE_YES"

        Req.Test.json(conn, %{
          "order_total" => "10",
          "prediction_order_metadata" => %{
            "minimum_contracts" => "23.8",
            "slippage_percentage" => "2"
          }
        })
      end)

      assert {:ok, preview} =
               Predictions.preview_yes(Fixtures.test_client(@stub_name), @product, "10")

      assert Predictions.extract_prediction_metadata(preview)["minimum_contracts"] == "23.8"
      assert Predictions.extract_prediction_metadata(%{}) == nil
    end

    test "preview_no can preview a sale" do
      Req.Test.expect(@stub_name, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)
        assert params["side"] == "SELL"
        assert params["order_configuration"] == %{"market_market_fok" => %{"base_size" => "4"}}
        Req.Test.json(conn, %{})
      end)

      assert {:ok, _} =
               Predictions.preview_no(Fixtures.test_client(@stub_name), @product, "4",
                 side: "SELL"
               )
    end
  end

  describe "discovery and positions" do
    test "list_markets reads the Kalshi catalogue and adds Coinbase product IDs" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.request_path == "/trade-api/v2/markets"
        assert conn.query_string == "status=open&series_ticker=KXBTC15M"

        Req.Test.json(conn, %{
          "markets" => [%{"ticker" => "KXBTC15M-26AUG272300-00", "yes_ask_dollars" => "0.52"}],
          "cursor" => "next"
        })
      end)

      kalshi = Kalshi.client(plug: {Req.Test, @stub_name})

      assert {:ok, [market], "next"} =
               Predictions.list_markets(Fixtures.test_client(@stub_name),
                 series_ticker: "KXBTC15M",
                 kalshi_client: kalshi
               )

      assert market["product_id"] == "KXBTC15M-26AUG272300-00-KALSHI"
      assert market["yes_ask_dollars"] == "0.52"
    end

    test "list_markets propagates Kalshi errors" do
      Req.Test.expect(@stub_name, fn conn ->
        conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"error" => "boom"})
      end)

      kalshi =
        Kalshi.client(plug: {Req.Test, @stub_name})
        |> Req.Request.merge_options(retry: false)

      assert {:error, {:api_error, 500, "boom"}} =
               Predictions.list_markets(Fixtures.test_client(@stub_name), kalshi_client: kalshi)
    end

    test "get_market fetches from Kalshi by product id and annotates it" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.request_path == "/trade-api/v2/markets/KXBTC-26SEP30-100K"
        Req.Test.json(conn, %{"market" => %{"ticker" => "KXBTC-26SEP30-100K"}})
      end)

      kalshi = Kalshi.client(plug: {Req.Test, @stub_name})

      assert {:ok, %{"product_id" => @product, "ticker" => "KXBTC-26SEP30-100K"}} =
               Predictions.get_market(Fixtures.test_client(@stub_name), @product, client: kalshi)
    end

    test "scan_coinbase_catalogue pages get_all_products and filters by -KALSHI suffix" do
      Req.Test.stub(@stub_name, fn conn ->
        query = URI.decode_query(conn.query_string)
        assert query["get_all_products"] == "true"

        case query["cursor"] do
          nil ->
            Req.Test.json(conn, %{
              "products" => [%{"product_id" => "BTC-USD", "product_type" => "SPOT"}],
              "pagination" => %{"has_next" => true, "next_cursor" => "c2"}
            })

          "c2" ->
            Req.Test.json(conn, %{
              "products" => [
                %{"product_id" => @product, "product_type" => "SPOT"},
                %{"product_id" => "X", "product_venue" => "PREDICTION_MARKETS"}
              ],
              "pagination" => %{"has_next" => false}
            })
        end
      end)

      assert {:ok, markets} =
               Predictions.scan_coinbase_catalogue(Fixtures.test_client(@stub_name))

      assert Enum.map(markets, & &1["product_id"]) == [@product, "X"]
    end

    test "scan_coinbase_catalogue accepts a custom filter and propagates errors" do
      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, %{"products" => [%{"product_id" => "A"}, %{"product_id" => "B"}]})
      end)

      assert {:ok, [%{"product_id" => "B"}]} =
               Predictions.scan_coinbase_catalogue(Fixtures.test_client(@stub_name),
                 filter: &(&1["product_id"] == "B")
               )

      Req.Test.stub(@stub_name, fn conn ->
        conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"error" => "boom"})
      end)

      assert {:error, {:api_error, 500, "boom"}} =
               Predictions.scan_coinbase_catalogue(Fixtures.test_client(@stub_name))
    end

    test "list_positions returns prediction positions from the portfolio breakdown" do
      position = %{
        "product_type" => "PRODUCT_TYPE_PREDICTION_MARKETS",
        "cbrn" => "cbrn:1",
        "prediction_markets" => %{
          "side" => "PREDICTION_MARKETS_POSITION_SIDE_LONG",
          "contracts_owned" => "12"
        }
      }

      short =
        put_in(position, ["prediction_markets", "side"], "PREDICTION_MARKETS_POSITION_SIDE_SHORT")

      Req.Test.expect(@stub_name, fn conn ->
        assert conn.request_path == "/api/v3/brokerage/portfolios/pf-1"

        Req.Test.json(conn, %{
          "breakdown" => %{
            "spot_positions" => [],
            "prediction_markets_positions" => [position, short]
          }
        })
      end)

      assert {:ok, positions} =
               Predictions.list_positions(Fixtures.test_client(@stub_name), "pf-1")

      assert length(positions) == 2
      assert [^position] = Predictions.filter_by_side(positions, "LONG")
      assert [^short] = Predictions.filter_by_side(positions, "SHORT")
      assert Predictions.extract_prediction_positions(%{"breakdown" => %{}}) == []
    end

    test "list_orders keeps only orders with a prediction side" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.query_string == "order_status=OPEN"

        Req.Test.json(conn, %{
          "orders" => [
            %{"order_id" => "1", "prediction_side" => "PREDICTION_SIDE_YES"},
            %{"order_id" => "2"},
            %{"order_id" => "3", "prediction_side" => "PREDICTION_SIDE_NO"}
          ]
        })
      end)

      assert {:ok, orders} =
               Predictions.list_orders(Fixtures.test_client(@stub_name), order_status: ["OPEN"])

      assert Enum.map(orders, & &1["order_id"]) == ["1", "3"]
    end

    test "constants" do
      assert Predictions.valid_sides() == ["PREDICTION_SIDE_YES", "PREDICTION_SIDE_NO"]
      assert Predictions.position_product_type() == "PRODUCT_TYPE_PREDICTION_MARKETS"
      assert Predictions.order_product_type() == "PREDICTION_MARKET"

      refute Predictions.prediction_market?(%{
               "product_type" => "SPOT",
               "product_id" => "BTC-USD"
             })

      assert Predictions.prediction_market?(%{"product_id" => "KXBTC15M-26AUG270830-30-KALSHI"})
      assert Predictions.prediction_market?(%{"product_type" => "PREDICTION_MARKET"})
    end
  end

  describe "default arguments" do
    test "helpers work without opts" do
      Req.Test.stub(@stub_name, fn conn ->
        body =
          case conn.request_path do
            "/api/v3/brokerage/products" -> %{"products" => []}
            "/api/v3/brokerage/orders/historical/batch" -> %{"orders" => []}
            _ -> Fixtures.sample_create_order_response()
          end

        Req.Test.json(conn, body)
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, _} = Predictions.buy_no(client, @product, "1")
      assert {:ok, _} = Predictions.sell_no(client, @product, "1")
      assert {:ok, _} = Predictions.preview_no(client, @product, "1")
      assert {:ok, _} = Predictions.preview_yes(client, @product, "1")
      assert {:ok, []} = Predictions.scan_coinbase_catalogue(client)
      assert {:ok, []} = Predictions.list_orders(client)

      assert {:ok, _} =
               Predictions.create_order(client, @product, "BUY", "PREDICTION_SIDE_YES", %{
                 market_market_ioc: %{quote_size: "1"}
               })
    end
  end
end
