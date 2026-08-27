defmodule ExCoinbase.Query do
  @moduledoc """
  Builds query strings for Coinbase Advanced Trade requests.

  The API expects array parameters as repeated keys
  (`product_ids=BTC-USD&product_ids=ETH-USD`, OpenAPI `explode: true`),
  which is not how `Req`'s `:params` option encodes lists. This module
  whitelists keys, drops `nil` values, expands lists into repeated keys and
  returns a URL with the encoded query appended.
  """

  @doc """
  Appends the allowed, non-nil options from `opts` to `path` as a query string.

  ## Examples

      iex> ExCoinbase.Query.url("/products", [limit: 10, cursor: nil], [:limit, :cursor])
      "/products?limit=10"

      iex> ExCoinbase.Query.url("/best_bid_ask", [product_ids: ["BTC-USD", "ETH-USD"]], [:product_ids])
      "/best_bid_ask?product_ids=BTC-USD&product_ids=ETH-USD"

      iex> ExCoinbase.Query.url("/time", [], [])
      "/time"
  """
  @spec url(String.t(), keyword(), [atom()]) :: String.t()
  def url(path, opts, allowed_keys) do
    case encode(opts, allowed_keys) do
      "" -> path
      query -> path <> "?" <> query
    end
  end

  @doc """
  Encodes the allowed, non-nil options from `opts` into a query string.

  List values become repeated keys; booleans, integers and strings are
  encoded with `to_string/1`.

  ## Examples

      iex> ExCoinbase.Query.encode([order_status: ["OPEN", "FILLED"], limit: 5], [:order_status, :limit])
      "order_status=OPEN&order_status=FILLED&limit=5"
  """
  @spec encode(keyword(), [atom()]) :: String.t()
  def encode(opts, allowed_keys) do
    opts
    |> Enum.filter(fn {key, value} -> key in allowed_keys and not is_nil(value) end)
    |> Enum.flat_map(&expand/1)
    |> URI.encode_query()
  end

  @spec expand({atom(), term()}) :: [{String.t(), String.t()}]
  defp expand({key, values}) when is_list(values) do
    Enum.map(values, fn value -> {Atom.to_string(key), to_string(value)} end)
  end

  defp expand({key, value}), do: [{Atom.to_string(key), to_string(value)}]
end
