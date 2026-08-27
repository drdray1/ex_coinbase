defmodule ExCoinbase.Accounts do
  @moduledoc """
  Coinbase Advanced Trade API - Account operations.

  Provides functions to list and retrieve account information
  including balances and holdings.

  ## Examples

      client = ExCoinbase.Client.new(api_key, private_key_pem)

      {:ok, response} = ExCoinbase.Accounts.list_accounts(client)
      accounts = ExCoinbase.Accounts.extract_accounts(response)

      btc_account = ExCoinbase.Accounts.find_by_currency(accounts, "BTC")
  """

  alias ExCoinbase.{Client, Query}

  @type client :: Req.Request.t()
  @type response :: {:ok, map()} | {:error, term()}

  @doc """
  Lists all accounts for the authenticated user.

  ## Options

    - `:limit` - Maximum number of accounts to return (default: 49, max: 250)
    - `:cursor` - Pagination cursor for next page

  ## Examples

      iex> list_accounts(client)
      {:ok, %{"accounts" => [%{"uuid" => "...", "currency" => "BTC", ...}]}}

      iex> list_accounts(client, limit: 100)
      {:ok, %{"accounts" => [...]}}
  """
  @spec list_accounts(client(), keyword()) :: response()
  def list_accounts(client, opts \\ []) do
    client
    |> Req.get(url: Query.url("/accounts", opts, [:limit, :cursor, :retail_portfolio_id]))
    |> Client.handle_response()
  end

  @doc """
  Retrieves a single account by UUID.

  ## Examples

      iex> get_account(client, "8bfc20d7-f7c6-4422-bf07-8243ca4169fe")
      {:ok, %{"account" => %{"uuid" => "...", "currency" => "BTC", ...}}}
  """
  @spec get_account(client(), String.t()) :: response()
  def get_account(client, account_uuid) do
    client
    |> Req.get(url: "/accounts/#{account_uuid}")
    |> Client.handle_response()
  end

  @doc """
  Extracts accounts list from response, normalizing to always return a list.

  ## Examples

      iex> extract_accounts(%{"accounts" => [%{"uuid" => "123"}]})
      [%{"uuid" => "123"}]

      iex> extract_accounts(%{})
      []
  """
  @spec extract_accounts(map()) :: list(map())
  def extract_accounts(%{"accounts" => accounts}) when is_list(accounts), do: accounts
  def extract_accounts(_), do: []

  @doc """
  Filters accounts down to prediction-market accounts
  (`ACCOUNT_TYPE_PREDICTION_MARKETS_TRANSFER | _EQUITY | _CFM`).

  ## Examples

      iex> prediction_accounts(accounts)
      [%{"type" => "ACCOUNT_TYPE_PREDICTION_MARKETS_EQUITY", ...}]
  """
  @spec prediction_accounts(list(map())) :: list(map())
  def prediction_accounts(accounts) when is_list(accounts) do
    Enum.filter(accounts, fn account ->
      is_binary(account["type"]) and
        String.starts_with?(account["type"], "ACCOUNT_TYPE_PREDICTION_MARKETS")
    end)
  end

  @doc """
  Extracts a single account from response.
  """
  @spec extract_account(map()) :: map() | nil
  def extract_account(%{"account" => account}) when is_map(account), do: account
  def extract_account(_), do: nil

  @doc """
  Finds an account by currency code.

  ## Examples

      iex> find_by_currency(accounts, "BTC")
      %{"uuid" => "...", "currency" => "BTC", ...}

      iex> find_by_currency(accounts, "DOGE")
      nil
  """
  @spec find_by_currency(list(map()), String.t()) :: map() | nil
  def find_by_currency(accounts, currency) do
    Enum.find(accounts, fn account ->
      account["currency"] == currency
    end)
  end

  @doc """
  Calculates total available balance across accounts in a given currency.

  Note: This only sums accounts with matching currency. For true portfolio
  value, you'd need to convert using current prices.

  ## Examples

      iex> total_available(accounts, "USD")
      #Decimal<1234.56>
  """
  @spec total_available(list(map()), String.t()) :: Decimal.t()
  def total_available(accounts, quote_currency) do
    accounts
    |> Enum.filter(fn account -> account["currency"] == quote_currency end)
    |> Enum.reduce(Decimal.new("0"), fn account, acc ->
      balance = get_in(account, ["available_balance", "value"]) || "0"
      Decimal.add(acc, Decimal.new(balance))
    end)
  end
end
