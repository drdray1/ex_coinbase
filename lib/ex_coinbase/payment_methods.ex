defmodule ExCoinbase.PaymentMethods do
  @moduledoc """
  Coinbase Advanced Trade API - Payment method operations.

  Lists and retrieves the payment methods (bank accounts, cards, etc.)
  linked to the authenticated user.

  ## Examples

      client = ExCoinbase.Client.new(api_key, private_key_pem)

      {:ok, response} = ExCoinbase.PaymentMethods.list(client)
      methods = ExCoinbase.PaymentMethods.extract_payment_methods(response)
  """

  alias ExCoinbase.Client

  @type client :: Req.Request.t()
  @type response :: {:ok, map()} | {:error, term()}

  @doc """
  Lists all payment methods for the authenticated user.

  ## Examples

      iex> list(client)
      {:ok, %{"payment_methods" => [%{"id" => "...", "type" => "ACH", ...}]}}
  """
  @spec list(client()) :: response()
  def list(client) do
    client
    |> Req.get(url: "/payment_methods")
    |> Client.handle_response()
  end

  @doc """
  Retrieves a single payment method by ID.

  ## Examples

      iex> get(client, "payment-method-id")
      {:ok, %{"payment_method" => %{"id" => "payment-method-id", ...}}}
  """
  @spec get(client(), String.t()) :: response()
  def get(client, payment_method_id) do
    client
    |> Req.get(url: "/payment_methods/#{payment_method_id}")
    |> Client.handle_response()
  end

  @doc """
  Extracts the payment methods list from a response, always returning a list.

  ## Examples

      iex> extract_payment_methods(%{"payment_methods" => [%{"id" => "pm-1"}]})
      [%{"id" => "pm-1"}]

      iex> extract_payment_methods(%{})
      []
  """
  @spec extract_payment_methods(map()) :: list(map())
  def extract_payment_methods(%{"payment_methods" => methods}) when is_list(methods), do: methods
  def extract_payment_methods(_), do: []
end
