defmodule ExCoinbase.Futures do
  @moduledoc """
  Coinbase Advanced Trade API - US regulated futures (CFM) operations.

  Provides access to the Coinbase Financial Markets (CFM) futures account:
  balance summary, positions, USD sweeps between the spot and futures
  accounts, and intraday margin settings.

  ## Examples

      client = ExCoinbase.Client.new(api_key, private_key_pem)

      {:ok, response} = ExCoinbase.Futures.balance_summary(client)
      summary = ExCoinbase.Futures.extract_balance_summary(response)

      {:ok, response} = ExCoinbase.Futures.list_positions(client)
      positions = ExCoinbase.Futures.extract_positions(response)
  """

  alias ExCoinbase.Client
  alias ExCoinbase.Query

  @type client :: Req.Request.t()
  @type response :: {:ok, map()} | {:error, term()}

  @valid_intraday_margin_settings ~w(INTRADAY_MARGIN_SETTING_STANDARD INTRADAY_MARGIN_SETTING_INTRADAY)

  @doc """
  Retrieves the futures balance summary.

  ## Examples

      iex> balance_summary(client)
      {:ok, %{"balance_summary" => %{"futures_buying_power" => %{...}, ...}}}
  """
  @spec balance_summary(client()) :: response()
  def balance_summary(client) do
    client
    |> Req.get(url: "/cfm/balance_summary")
    |> Client.handle_response()
  end

  @doc """
  Lists all open futures positions.

  ## Examples

      iex> list_positions(client)
      {:ok, %{"positions" => [%{"product_id" => "BIT-28FEB25-CDE", ...}]}}
  """
  @spec list_positions(client()) :: response()
  def list_positions(client) do
    client
    |> Req.get(url: "/cfm/positions")
    |> Client.handle_response()
  end

  @doc """
  Retrieves a single futures position by product ID.

  ## Examples

      iex> get_position(client, "BIT-28FEB25-CDE")
      {:ok, %{"position" => %{"product_id" => "BIT-28FEB25-CDE", ...}}}
  """
  @spec get_position(client(), String.t()) :: response()
  def get_position(client, product_id) do
    client
    |> Req.get(url: "/cfm/positions/#{product_id}")
    |> Client.handle_response()
  end

  @doc """
  Schedules a USD sweep from the futures account to the spot account.

  ## Examples

      iex> schedule_sweep(client, "100.00")
      {:ok, %{"success" => true}}
  """
  @spec schedule_sweep(client(), String.t()) :: response()
  def schedule_sweep(client, usd_amount) do
    client
    |> Req.post(url: "/cfm/sweeps/schedule", json: %{usd_amount: usd_amount})
    |> Client.handle_response()
  end

  @doc """
  Lists pending and processing sweeps.

  ## Examples

      iex> list_sweeps(client)
      {:ok, %{"sweeps" => [%{"id" => "...", "status" => "PENDING", ...}]}}
  """
  @spec list_sweeps(client()) :: response()
  def list_sweeps(client) do
    client
    |> Req.get(url: "/cfm/sweeps")
    |> Client.handle_response()
  end

  @doc """
  Cancels any pending sweep.

  ## Examples

      iex> cancel_sweep(client)
      {:ok, %{"success" => true}}
  """
  @spec cancel_sweep(client()) :: response()
  def cancel_sweep(client) do
    client
    |> Req.delete(url: "/cfm/sweeps")
    |> Client.handle_response()
  end

  @doc """
  Retrieves the current intraday margin setting.

  ## Examples

      iex> get_intraday_margin_setting(client)
      {:ok, %{"setting" => "INTRADAY_MARGIN_SETTING_STANDARD"}}
  """
  @spec get_intraday_margin_setting(client()) :: response()
  def get_intraday_margin_setting(client) do
    client
    |> Req.get(url: "/cfm/intraday/margin_setting")
    |> Client.handle_response()
  end

  @doc """
  Sets the intraday margin setting.

  `setting` must be one of `valid_intraday_margin_settings/0`.

  ## Examples

      iex> set_intraday_margin_setting(client, "INTRADAY_MARGIN_SETTING_INTRADAY")
      {:ok, %{}}

      iex> set_intraday_margin_setting(client, "BOGUS")
      {:error, {:validation_error, ["setting must be one of: INTRADAY_MARGIN_SETTING_STANDARD, INTRADAY_MARGIN_SETTING_INTRADAY"]}}
  """
  @spec set_intraday_margin_setting(client(), String.t()) ::
          response() | {:error, {:validation_error, [String.t()]}}
  def set_intraday_margin_setting(client, setting)
      when setting in @valid_intraday_margin_settings do
    client
    |> Req.post(url: "/cfm/intraday/margin_setting", json: %{setting: setting})
    |> Client.handle_response()
  end

  def set_intraday_margin_setting(_client, _setting) do
    message = "setting must be one of: #{Enum.join(@valid_intraday_margin_settings, ", ")}"
    {:error, {:validation_error, [message]}}
  end

  @doc """
  Retrieves the current margin window.

  ## Options

    - `:margin_profile_type` - Margin profile type to query

  ## Examples

      iex> current_margin_window(client)
      {:ok, %{"margin_window" => %{...}, "is_intraday_margin_killswitch_enabled" => false}}
  """
  @spec current_margin_window(client(), keyword()) :: response()
  def current_margin_window(client, opts \\ []) do
    client
    |> Req.get(
      url: Query.url("/cfm/intraday/current_margin_window", opts, [:margin_profile_type])
    )
    |> Client.handle_response()
  end

  @doc """
  Returns the list of valid intraday margin settings.
  """
  @spec valid_intraday_margin_settings() :: list(String.t())
  def valid_intraday_margin_settings, do: @valid_intraday_margin_settings

  @doc """
  Extracts the balance summary from a response.

  ## Examples

      iex> extract_balance_summary(%{"balance_summary" => %{"total_usd_balance" => %{}}})
      %{"total_usd_balance" => %{}}

      iex> extract_balance_summary(%{})
      nil
  """
  @spec extract_balance_summary(map()) :: map() | nil
  def extract_balance_summary(%{"balance_summary" => summary}) when is_map(summary), do: summary
  def extract_balance_summary(_), do: nil

  @doc """
  Extracts the positions list from a response, always returning a list.

  ## Examples

      iex> extract_positions(%{"positions" => [%{"product_id" => "BIT-28FEB25-CDE"}]})
      [%{"product_id" => "BIT-28FEB25-CDE"}]

      iex> extract_positions(%{})
      []
  """
  @spec extract_positions(map()) :: list(map())
  def extract_positions(%{"positions" => positions}) when is_list(positions), do: positions
  def extract_positions(_), do: []
end
