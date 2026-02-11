defmodule ExCoinbase.Orders do
  @moduledoc """
  Coinbase Advanced Trade API - Order management.

  Provides functions for placing, canceling, and retrieving orders.
  Supports market, limit, stop-limit, and bracket order types.

  ## Examples

      client = ExCoinbase.Client.new(api_key, private_key_pem)

      # Market order - spend $100 on BTC
      {:ok, resp} = ExCoinbase.Orders.market_order_quote(client, "BTC-USD", "BUY", "100")

      # Limit order
      {:ok, resp} = ExCoinbase.Orders.limit_order_gtc(client, "BTC-USD", "BUY", "0.001", "50000")

      # Bracket order with take-profit and stop-loss
      {:ok, resp} = ExCoinbase.Orders.bracket_order_gtc(
        client, "BTC-USD", "BUY", "0.01", "45000", "50000", "43000"
      )
  """

  alias ExCoinbase.Client

  @type client :: Req.Request.t()
  @type response :: {:ok, map()} | {:error, term()}
  @type order_id :: String.t()
  @type product_id :: String.t()

  @valid_sides ~w(BUY SELL)
  @valid_order_types ~w(MARKET LIMIT STOP STOP_LIMIT BRACKET)
  @valid_time_in_force ~w(GTC GTD IOC FOK)
  @valid_order_statuses ~w(OPEN CANCELLED EXPIRED FILLED PENDING)

  # ============================================================================
  # Order Placement
  # ============================================================================

  @doc """
  Creates a new order.

  ## Parameters

    - `client` - Authenticated client
    - `params` - Order parameters
      - `:product_id` - Trading pair (e.g., "BTC-USD") - required
      - `:side` - "BUY" or "SELL" - required
      - `:order_configuration` - Type-specific config - required

  ## Order Configuration Examples

  Market order (quote size - spend $100):

      %{market_market_ioc: %{quote_size: "100"}}

  Limit GTC order:

      %{limit_limit_gtc: %{base_size: "0.001", limit_price: "50000"}}

  Stop-limit GTC order:

      %{stop_limit_stop_limit_gtc: %{base_size: "0.001", limit_price: "49000", stop_price: "48000"}}
  """
  @spec create_order(client(), map()) :: response()
  def create_order(client, params) do
    with {:ok, validated} <- validate_create_order_params(params) do
      body = build_order_body(validated)

      client
      |> Req.post(url: "/orders", json: body)
      |> Client.handle_response()
    end
  end

  @doc """
  Creates a market order using quote currency amount.

  ## Examples

      iex> market_order_quote(client, "BTC-USD", "BUY", "100")
      {:ok, %{"order_id" => "..."}}
  """
  @spec market_order_quote(client(), product_id(), String.t(), String.t()) :: response()
  def market_order_quote(client, product_id, side, quote_size) do
    create_order(client, %{
      product_id: product_id,
      side: side,
      order_configuration: %{market_market_ioc: %{quote_size: quote_size}}
    })
  end

  @doc """
  Creates a market order using base currency amount.

  ## Examples

      iex> market_order_base(client, "BTC-USD", "BUY", "0.001")
      {:ok, %{"order_id" => "..."}}
  """
  @spec market_order_base(client(), product_id(), String.t(), String.t()) :: response()
  def market_order_base(client, product_id, side, base_size) do
    create_order(client, %{
      product_id: product_id,
      side: side,
      order_configuration: %{market_market_ioc: %{base_size: base_size}}
    })
  end

  @doc """
  Creates a limit order with Good-Til-Canceled duration.

  ## Examples

      iex> limit_order_gtc(client, "BTC-USD", "BUY", "0.001", "50000")
      {:ok, %{"order_id" => "..."}}
  """
  @spec limit_order_gtc(client(), product_id(), String.t(), String.t(), String.t()) :: response()
  def limit_order_gtc(client, product_id, side, base_size, limit_price) do
    create_order(client, %{
      product_id: product_id,
      side: side,
      order_configuration: %{
        limit_limit_gtc: %{
          base_size: base_size,
          limit_price: limit_price
        }
      }
    })
  end

  @doc """
  Creates a stop-limit order with Good-Til-Canceled duration.

  ## Examples

      iex> stop_limit_order_gtc(client, "BTC-USD", "SELL", "0.001", "49000", "48000")
      {:ok, %{"order_id" => "..."}}
  """
  @spec stop_limit_order_gtc(
          client(),
          product_id(),
          String.t(),
          String.t(),
          String.t(),
          String.t()
        ) :: response()
  def stop_limit_order_gtc(client, product_id, side, base_size, limit_price, stop_price) do
    create_order(client, %{
      product_id: product_id,
      side: side,
      order_configuration: %{
        stop_limit_stop_limit_gtc: %{
          base_size: base_size,
          limit_price: limit_price,
          stop_price: stop_price
        }
      }
    })
  end

  @doc """
  Creates a bracket order with entry limit, take-profit, and stop-loss (Good-Til-Canceled).

  When the entry order fills, Coinbase automatically activates the TP and SL orders.
  When one exit leg fills, the other is automatically cancelled (OCO).

  ## Examples

      iex> bracket_order_gtc(client, "BTC-USD", "BUY", "0.01", "45000", "50000", "43000")
      {:ok, %{"order_id" => "...", "success" => true}}
  """
  @spec bracket_order_gtc(
          client(),
          product_id(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t()
        ) :: response()
  def bracket_order_gtc(
        client,
        product_id,
        side,
        base_size,
        entry_price,
        take_profit_price,
        stop_loss_price
      ) do
    create_order(client, %{
      product_id: product_id,
      side: side,
      order_configuration: %{
        limit_limit_gtc: %{
          base_size: base_size,
          limit_price: entry_price
        }
      },
      attached_order_configuration: %{
        trigger_bracket_gtc: %{
          limit_price: take_profit_price,
          stop_trigger_price: stop_loss_price
        }
      }
    })
  end

  @doc """
  Creates a bracket order with entry limit, take-profit, and stop-loss (Good-Til-Date).

  Same as `bracket_order_gtc/7` but the order expires at the specified `end_time`.

  ## Examples

      iex> bracket_order_gtd(client, "BTC-USD", "BUY", "0.01", "45000", "50000", "43000", "2024-12-31T23:59:59Z")
      {:ok, %{"order_id" => "...", "success" => true}}
  """
  @spec bracket_order_gtd(
          client(),
          product_id(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t()
        ) :: response()
  def bracket_order_gtd(
        client,
        product_id,
        side,
        base_size,
        entry_price,
        take_profit_price,
        stop_loss_price,
        end_time
      ) do
    create_order(client, %{
      product_id: product_id,
      side: side,
      order_configuration: %{
        limit_limit_gtd: %{
          base_size: base_size,
          limit_price: entry_price,
          end_time: end_time
        }
      },
      attached_order_configuration: %{
        trigger_bracket_gtd: %{
          limit_price: take_profit_price,
          stop_trigger_price: stop_loss_price,
          end_time: end_time
        }
      }
    })
  end

  # ============================================================================
  # Order Cancellation
  # ============================================================================

  @doc """
  Cancels one or more orders.

  ## Examples

      iex> cancel_orders(client, ["order-id-1", "order-id-2"])
      {:ok, %{"results" => [%{"order_id" => "...", "success" => true}]}}
  """
  @spec cancel_orders(client(), list(order_id())) :: response()
  def cancel_orders(client, order_ids) when is_list(order_ids) do
    body = %{order_ids: order_ids}

    client
    |> Req.post(url: "/orders/batch_cancel", json: body)
    |> Client.handle_response()
  end

  @doc """
  Cancels a single order.
  """
  @spec cancel_order(client(), order_id()) :: response()
  def cancel_order(client, order_id) do
    cancel_orders(client, [order_id])
  end

  # ============================================================================
  # Order Retrieval
  # ============================================================================

  @doc """
  Lists orders with optional filtering.

  ## Options

    - `:product_id` - Filter by product
    - `:order_status` - Filter by status (OPEN, CANCELLED, EXPIRED, FILLED, PENDING)
    - `:limit` - Maximum orders to return
    - `:start_date` - Start date filter
    - `:end_date` - End date filter
    - `:order_type` - Filter by order type
    - `:order_side` - Filter by side (BUY, SELL)
    - `:cursor` - Pagination cursor

  ## Examples

      iex> list_orders(client, product_id: "BTC-USD", order_status: "OPEN")
      {:ok, %{"orders" => [...]}}
  """
  @spec list_orders(client(), keyword()) :: response()
  def list_orders(client, opts \\ []) do
    query =
      build_query(opts, [
        :product_id,
        :order_status,
        :limit,
        :start_date,
        :end_date,
        :order_type,
        :order_side,
        :cursor
      ])

    client
    |> Req.get(url: "/orders/historical/batch", params: query)
    |> Client.handle_response()
  end

  @doc """
  Retrieves a single order by ID.

  ## Examples

      iex> get_order(client, "order-id-1")
      {:ok, %{"order" => %{"order_id" => "...", "status" => "FILLED"}}}
  """
  @spec get_order(client(), order_id()) :: response()
  def get_order(client, order_id) do
    client
    |> Req.get(url: "/orders/historical/#{order_id}")
    |> Client.handle_response()
  end

  @doc """
  Lists fills (executed trades) with optional filtering.

  ## Options

    - `:order_id` - Filter by order ID
    - `:product_id` - Filter by product
    - `:start_sequence_timestamp` - Start time
    - `:end_sequence_timestamp` - End time
    - `:limit` - Maximum fills to return
    - `:cursor` - Pagination cursor

  ## Examples

      iex> list_fills(client, product_id: "BTC-USD")
      {:ok, %{"fills" => [...]}}
  """
  @spec list_fills(client(), keyword()) :: response()
  def list_fills(client, opts \\ []) do
    query =
      build_query(opts, [
        :order_id,
        :product_id,
        :start_sequence_timestamp,
        :end_sequence_timestamp,
        :limit,
        :cursor
      ])

    client
    |> Req.get(url: "/orders/historical/fills", params: query)
    |> Client.handle_response()
  end

  # ============================================================================
  # Validation
  # ============================================================================

  @doc """
  Validates order parameters before submission.

  ## Examples

      iex> validate_order_params(%{product_id: "BTC-USD", side: "BUY", order_configuration: %{...}})
      {:ok, %{...}}

      iex> validate_order_params(%{})
      {:error, ["product_id is required", ...]}
  """
  @spec validate_order_params(map()) :: {:ok, map()} | {:error, list(String.t())}
  def validate_order_params(params) when is_map(params) do
    errors =
      []
      |> validate_required(params, :product_id, "product_id is required")
      |> validate_required(params, :side, "side is required")
      |> validate_required(params, :order_configuration, "order_configuration is required")
      |> validate_side(params)
      |> validate_order_configuration(params)

    case errors do
      [] -> {:ok, params}
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  def validate_order_params(_), do: {:error, ["params must be a map"]}

  @doc "Returns valid order sides"
  @spec valid_sides() :: list(String.t())
  def valid_sides, do: @valid_sides

  @doc "Returns valid order types"
  @spec valid_order_types() :: list(String.t())
  def valid_order_types, do: @valid_order_types

  @doc "Returns valid time-in-force values"
  @spec valid_time_in_force() :: list(String.t())
  def valid_time_in_force, do: @valid_time_in_force

  @doc "Returns valid order statuses"
  @spec valid_order_statuses() :: list(String.t())
  def valid_order_statuses, do: @valid_order_statuses

  # ============================================================================
  # Extractors
  # ============================================================================

  @doc "Extracts orders list from response."
  @spec extract_orders(map()) :: list(map())
  def extract_orders(%{"orders" => orders}) when is_list(orders), do: orders
  def extract_orders(_), do: []

  @doc "Extracts fills list from response."
  @spec extract_fills(map()) :: list(map())
  def extract_fills(%{"fills" => fills}) when is_list(fills), do: fills
  def extract_fills(_), do: []

  @doc "Extracts order from single order response."
  @spec extract_order(map()) :: map() | nil
  def extract_order(%{"order" => order}) when is_map(order), do: order
  def extract_order(_), do: nil

  @doc "Filters orders by status."
  @spec filter_by_status(list(map()), String.t()) :: list(map())
  def filter_by_status(orders, status) do
    Enum.filter(orders, fn order -> order["status"] == status end)
  end

  @doc "Filters orders by product."
  @spec filter_by_product(list(map()), product_id()) :: list(map())
  def filter_by_product(orders, product_id) do
    Enum.filter(orders, fn order -> order["product_id"] == product_id end)
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  @spec validate_create_order_params(map()) :: {:ok, map()} | {:error, term()}
  defp validate_create_order_params(params) do
    case validate_order_params(params) do
      {:ok, _} -> {:ok, params}
      {:error, errors} -> {:error, {:validation_error, errors}}
    end
  end

  @spec build_order_body(map()) :: map()
  defp build_order_body(params) do
    %{
      client_order_id: generate_client_order_id(),
      product_id: get_field(params, :product_id),
      side: get_field(params, :side),
      order_configuration: get_field(params, :order_configuration)
    }
    |> maybe_add_field(params, :attached_order_configuration)
    |> maybe_add_field(params, :leverage)
    |> maybe_add_field(params, :margin_type)
    |> maybe_add_field(params, :retail_portfolio_id)
  end

  @spec generate_client_order_id() :: String.t()
  defp generate_client_order_id do
    <<a1::4, a2::4, a3::4, a4::4, a5::4, a6::4, a7::4, a8::4, b1::4, b2::4, b3::4, b4::4, _::4,
      c2::4, c3::4, c4::4, _::2, d2::6, d3::4, d4::4, e1::4, e2::4, e3::4, e4::4, e5::4, e6::4,
      e7::4, e8::4, e9::4, e10::4, e11::4, e12::4>> =
      :crypto.strong_rand_bytes(16)

    hex = ~c"0123456789abcdef"

    IO.iodata_to_binary([
      Enum.at(hex, a1),
      Enum.at(hex, a2),
      Enum.at(hex, a3),
      Enum.at(hex, a4),
      Enum.at(hex, a5),
      Enum.at(hex, a6),
      Enum.at(hex, a7),
      Enum.at(hex, a8),
      ?-,
      Enum.at(hex, b1),
      Enum.at(hex, b2),
      Enum.at(hex, b3),
      Enum.at(hex, b4),
      ?-,
      ?4,
      Enum.at(hex, c2),
      Enum.at(hex, c3),
      Enum.at(hex, c4),
      ?-,
      Enum.at(hex, 8 + rem(d2, 4)),
      Enum.at(hex, d3),
      Enum.at(hex, d4),
      Enum.at(hex, e1),
      ?-,
      Enum.at(hex, e2),
      Enum.at(hex, e3),
      Enum.at(hex, e4),
      Enum.at(hex, e5),
      Enum.at(hex, e6),
      Enum.at(hex, e7),
      Enum.at(hex, e8),
      Enum.at(hex, e9),
      Enum.at(hex, e10),
      Enum.at(hex, e11),
      Enum.at(hex, e12),
      Enum.at(hex, a1)
    ])
  end

  @spec validate_required(list(), map(), atom(), String.t()) :: list()
  defp validate_required(errors, params, field, message) do
    case get_field(params, field) do
      nil -> [message | errors]
      "" -> [message | errors]
      _ -> errors
    end
  end

  @spec validate_side(list(), map()) :: list()
  defp validate_side(errors, params) do
    side = get_field(params, :side)

    cond do
      is_nil(side) -> errors
      side in @valid_sides -> errors
      true -> ["side must be one of: #{Enum.join(@valid_sides, ", ")}" | errors]
    end
  end

  @spec validate_order_configuration(list(), map()) :: list()
  defp validate_order_configuration(errors, params) do
    config = get_field(params, :order_configuration)

    cond do
      is_nil(config) -> errors
      not is_map(config) -> ["order_configuration must be a map" | errors]
      map_size(config) == 0 -> ["order_configuration cannot be empty" | errors]
      true -> errors
    end
  end

  @spec get_field(map(), atom()) :: term()
  defp get_field(params, field) when is_atom(field) do
    Map.get(params, field) || Map.get(params, Atom.to_string(field))
  end

  @spec maybe_add_field(map(), map(), atom()) :: map()
  defp maybe_add_field(body, params, field) do
    case get_field(params, field) do
      nil -> body
      value -> Map.put(body, field, value)
    end
  end

  @spec build_query(keyword(), list(atom())) :: keyword()
  defp build_query(opts, allowed_keys) do
    opts
    |> Keyword.take(allowed_keys)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end
end
