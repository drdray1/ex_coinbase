defmodule ExCoinbase.Predictions.KalshiTest do
  use ExUnit.Case, async: true

  alias ExCoinbase.Predictions.Kalshi

  @stub_name ExCoinbase.Predictions.KalshiTest
  @ticker "KXBTC15M-26AUG272300-00"
  @base "/trade-api/v2"

  defp kalshi_client do
    Kalshi.client(plug: {Req.Test, @stub_name}) |> Req.Request.merge_options(retry: false)
  end

  describe "client/1" do
    test "defaults to the public Kalshi API and honours base_url" do
      assert Kalshi.client().options[:base_url] == "https://api.elections.kalshi.com/trade-api/v2"
      assert Kalshi.client(base_url: "http://x").options[:base_url] == "http://x"
      assert Kalshi.client(req_options: [max_retries: 0]).options[:max_retries] == 0
      refute Map.has_key?(Kalshi.client().options, :plug)
    end
  end

  describe "list_markets/1" do
    test "encodes filters, including list tickers" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.request_path == @base <> "/markets"

        assert conn.query_string ==
                 "series_ticker=KXBTC15M&status=open&tickers=A&tickers=B&limit=2"

        Req.Test.json(conn, %{"markets" => [%{"ticker" => @ticker}], "cursor" => "c1"})
      end)

      assert {:ok, %{"markets" => [%{"ticker" => @ticker}], "cursor" => "c1"}} =
               Kalshi.list_markets(
                 client: kalshi_client(),
                 series_ticker: "KXBTC15M",
                 status: "open",
                 tickers: ["A", "B"],
                 limit: 2,
                 bogus: 1
               )
    end

    test "surfaces API errors" do
      Req.Test.expect(@stub_name, fn conn ->
        conn |> Plug.Conn.put_status(429) |> Req.Test.json(%{})
      end)

      assert {:error, :rate_limited} = Kalshi.list_markets(client: kalshi_client())
    end
  end

  describe "get_market/2" do
    test "strips the -KALSHI suffix and fetches by ticker" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.request_path == @base <> "/markets/#{@ticker}"
        Req.Test.json(conn, %{"market" => %{"ticker" => @ticker}})
      end)

      assert {:ok, %{"market" => %{"ticker" => @ticker}}} =
               Kalshi.get_market(@ticker <> "-KALSHI", client: kalshi_client())
    end
  end

  describe "list_events/1 and list_series/1" do
    test "hit their endpoints with allowed params" do
      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, %{"path" => conn.request_path, "query" => conn.query_string})
      end)

      assert {:ok,
              %{
                "path" => @base <> "/events",
                "query" => "series_ticker=KXBTC15M&with_nested_markets=true"
              }} =
               Kalshi.list_events(
                 client: kalshi_client(),
                 series_ticker: "KXBTC15M",
                 with_nested_markets: true
               )

      assert {:ok, %{"path" => @base <> "/series", "query" => "category=Crypto"}} =
               Kalshi.list_series(client: kalshi_client(), category: "Crypto")
    end
  end

  describe "id mapping" do
    test "to_product_id / from_product_id are inverse and idempotent" do
      assert Kalshi.to_product_id(@ticker) == @ticker <> "-KALSHI"
      assert Kalshi.to_product_id(@ticker <> "-KALSHI") == @ticker <> "-KALSHI"
      assert Kalshi.from_product_id(@ticker <> "-KALSHI") == @ticker
      assert Kalshi.from_product_id(@ticker) == @ticker
    end

    test "with_product_id annotates market maps" do
      assert %{"product_id" => "X-KALSHI", "ticker" => "X"} =
               Kalshi.with_product_id(%{"ticker" => "X"})

      assert Kalshi.with_product_id(%{"foo" => 1}) == %{"foo" => 1}
    end
  end
end

defmodule ExCoinbase.Predictions.KalshiConfigTest do
  # Mutates global application config, so it must not run alongside async tests.
  use ExUnit.Case, async: false

  alias ExCoinbase.Predictions.Kalshi

  test "default client reads kalshi_url / kalshi_req_options from application config" do
    previous = Application.get_env(:ex_coinbase, :config, [])

    Application.put_env(
      :ex_coinbase,
      :config,
      previous
      |> Keyword.put(:kalshi_url, "http://127.0.0.1:1")
      |> Keyword.put(:kalshi_req_options, retry: false)
    )

    on_exit(fn -> Application.put_env(:ex_coinbase, :config, previous) end)

    client = Kalshi.client()
    assert client.options[:base_url] == "http://127.0.0.1:1"
    assert client.options[:retry] == false

    assert {:error, {:connection_error, _}} = Kalshi.list_series()
    assert {:error, {:connection_error, _}} = Kalshi.list_markets()
    assert {:error, {:connection_error, _}} = Kalshi.list_events()
    assert {:error, {:connection_error, _}} = Kalshi.get_market("X-KALSHI")
  end
end
