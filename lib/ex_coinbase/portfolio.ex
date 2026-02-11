defmodule ExCoinbase.Portfolio do
  @moduledoc """
  Coinbase Advanced Trade API - Portfolio management.

  Provides functions for managing portfolios, including listing,
  creating, moving funds, and retrieving portfolio breakdowns.

  ## Examples

      client = ExCoinbase.Client.new(api_key, private_key_pem)

      {:ok, resp} = ExCoinbase.Portfolio.list_portfolios(client)
      {:ok, resp} = ExCoinbase.Portfolio.create_portfolio(client, "Trading Portfolio")
      {:ok, resp} = ExCoinbase.Portfolio.get_portfolio_breakdown(client, "portfolio-uuid")
  """

  alias ExCoinbase.Client

  @type client :: Req.Request.t()
  @type response :: {:ok, map()} | {:error, term()}
  @type portfolio_uuid :: String.t()

  @valid_portfolio_types ~w(DEFAULT CONSUMER INTX)

  # ============================================================================
  # Portfolio Operations
  # ============================================================================

  @doc """
  Lists all portfolios for the authenticated user.

  ## Options

    - `:portfolio_type` - Filter by type (DEFAULT, CONSUMER, INTX)

  ## Examples

      iex> list_portfolios(client)
      {:ok, %{"portfolios" => [%{"uuid" => "...", "name" => "Default", ...}]}}
  """
  @spec list_portfolios(client(), keyword()) :: response()
  def list_portfolios(client, opts \\ []) do
    query = build_query(opts, [:portfolio_type])

    client
    |> Req.get(url: "/portfolios", params: query)
    |> Client.handle_response()
  end

  @doc """
  Creates a new portfolio.

  ## Examples

      iex> create_portfolio(client, "Trading Portfolio")
      {:ok, %{"portfolio" => %{"uuid" => "...", "name" => "Trading Portfolio"}}}
  """
  @spec create_portfolio(client(), String.t()) :: response()
  def create_portfolio(client, name) do
    client
    |> Req.post(url: "/portfolios", json: %{name: name})
    |> Client.handle_response()
  end

  @doc """
  Retrieves breakdown of a portfolio's holdings.

  ## Examples

      iex> get_portfolio_breakdown(client, "portfolio-uuid")
      {:ok, %{"breakdown" => %{"portfolio" => %{...}, "spot_positions" => [...]}}}
  """
  @spec get_portfolio_breakdown(client(), portfolio_uuid()) :: response()
  def get_portfolio_breakdown(client, portfolio_uuid) do
    client
    |> Req.get(url: "/portfolios/#{portfolio_uuid}")
    |> Client.handle_response()
  end

  @doc """
  Moves funds between portfolios.

  ## Parameters

    - `params` - Move parameters
      - `:source_portfolio_uuid` - Source portfolio UUID
      - `:target_portfolio_uuid` - Target portfolio UUID
      - `:funds` - Map with `:value` and `:currency`

  ## Examples

      iex> move_funds(client, %{
      ...>   source_portfolio_uuid: "source-uuid",
      ...>   target_portfolio_uuid: "target-uuid",
      ...>   funds: %{value: "100.00", currency: "USD"}
      ...> })
      {:ok, %{"source_portfolio_uuid" => "...", "target_portfolio_uuid" => "..."}}
  """
  @spec move_funds(client(), map()) :: response()
  def move_funds(client, params) do
    with {:ok, body} <- validate_move_funds_params(params) do
      client
      |> Req.post(url: "/portfolios/move_funds", json: body)
      |> Client.handle_response()
    end
  end

  @doc """
  Deletes a portfolio. Only empty portfolios can be deleted.

  ## Examples

      iex> delete_portfolio(client, "portfolio-uuid")
      {:ok, %{}}
  """
  @spec delete_portfolio(client(), portfolio_uuid()) :: response()
  def delete_portfolio(client, portfolio_uuid) do
    client
    |> Req.delete(url: "/portfolios/#{portfolio_uuid}")
    |> Client.handle_response()
  end

  @doc """
  Edits a portfolio's name.

  ## Examples

      iex> edit_portfolio(client, "portfolio-uuid", "New Name")
      {:ok, %{"portfolio" => %{"uuid" => "...", "name" => "New Name"}}}
  """
  @spec edit_portfolio(client(), portfolio_uuid(), String.t()) :: response()
  def edit_portfolio(client, portfolio_uuid, name) do
    client
    |> Req.put(url: "/portfolios/#{portfolio_uuid}", json: %{name: name})
    |> Client.handle_response()
  end

  # ============================================================================
  # Extractors
  # ============================================================================

  @doc "Extracts portfolios list from response."
  @spec extract_portfolios(map()) :: list(map())
  def extract_portfolios(%{"portfolios" => portfolios}) when is_list(portfolios), do: portfolios
  def extract_portfolios(_), do: []

  @doc "Extracts portfolio from single portfolio response."
  @spec extract_portfolio(map()) :: map() | nil
  def extract_portfolio(%{"portfolio" => portfolio}) when is_map(portfolio), do: portfolio
  def extract_portfolio(_), do: nil

  @doc "Extracts breakdown from portfolio breakdown response."
  @spec extract_breakdown(map()) :: map() | nil
  def extract_breakdown(%{"breakdown" => breakdown}) when is_map(breakdown), do: breakdown
  def extract_breakdown(_), do: nil

  @doc "Finds portfolio by name."
  @spec find_by_name(list(map()), String.t()) :: map() | nil
  def find_by_name(portfolios, name) do
    Enum.find(portfolios, fn portfolio -> portfolio["name"] == name end)
  end

  @doc "Finds the default portfolio."
  @spec find_default(list(map())) :: map() | nil
  def find_default(portfolios) do
    Enum.find(portfolios, fn portfolio -> portfolio["type"] == "DEFAULT" end)
  end

  @doc "Extracts spot positions from breakdown."
  @spec extract_spot_positions(map()) :: list(map())
  def extract_spot_positions(%{"spot_positions" => positions}) when is_list(positions),
    do: positions

  def extract_spot_positions(%{"breakdown" => %{"spot_positions" => positions}})
      when is_list(positions),
      do: positions

  def extract_spot_positions(_), do: []

  @doc "Calculates total portfolio value from breakdown."
  @spec total_value(map()) :: Decimal.t()
  def total_value(breakdown) do
    breakdown
    |> get_in(["portfolio_balances", "total_balance", "value"])
    |> parse_decimal()
  end

  @doc "Returns valid portfolio types"
  @spec valid_portfolio_types() :: list(String.t())
  def valid_portfolio_types, do: @valid_portfolio_types

  # ============================================================================
  # Private Functions
  # ============================================================================

  @spec validate_move_funds_params(map()) :: {:ok, map()} | {:error, term()}
  defp validate_move_funds_params(params) do
    errors =
      []
      |> validate_required(params, :source_portfolio_uuid, "source_portfolio_uuid is required")
      |> validate_required(params, :target_portfolio_uuid, "target_portfolio_uuid is required")
      |> validate_required(params, :funds, "funds is required")
      |> validate_funds(params)

    case errors do
      [] -> {:ok, normalize_move_funds_params(params)}
      errors -> {:error, {:validation_error, Enum.reverse(errors)}}
    end
  end

  @spec normalize_move_funds_params(map()) :: map()
  defp normalize_move_funds_params(params) do
    %{
      source_portfolio_uuid: get_field(params, :source_portfolio_uuid),
      target_portfolio_uuid: get_field(params, :target_portfolio_uuid),
      funds: get_field(params, :funds)
    }
  end

  @spec validate_required(list(), map(), atom(), String.t()) :: list()
  defp validate_required(errors, params, field, message) do
    case get_field(params, field) do
      nil -> [message | errors]
      "" -> [message | errors]
      _ -> errors
    end
  end

  @spec validate_funds(list(), map()) :: list()
  defp validate_funds(errors, params) do
    funds = get_field(params, :funds)

    cond do
      is_nil(funds) ->
        errors

      not is_map(funds) ->
        ["funds must be a map with value and currency" | errors]

      is_nil(funds["value"]) and is_nil(funds[:value]) ->
        ["funds.value is required" | errors]

      is_nil(funds["currency"]) and is_nil(funds[:currency]) ->
        ["funds.currency is required" | errors]

      true ->
        errors
    end
  end

  @spec get_field(map(), atom()) :: term()
  defp get_field(params, field) when is_atom(field) do
    Map.get(params, field) || Map.get(params, Atom.to_string(field))
  end

  @spec parse_decimal(String.t() | nil) :: Decimal.t()
  defp parse_decimal(nil), do: Decimal.new("0")
  defp parse_decimal(value) when is_binary(value), do: Decimal.new(value)
  defp parse_decimal(_), do: Decimal.new("0")

  @spec build_query(keyword(), list(atom())) :: keyword()
  defp build_query(opts, allowed_keys) do
    opts
    |> Keyword.take(allowed_keys)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end
end
