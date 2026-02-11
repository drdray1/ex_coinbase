defmodule ExCoinbase.WebSocket do
  @moduledoc """
  Coinbase Advanced Trade WebSocket Streaming API.

  Handles WebSocket message construction and parsing for the Coinbase
  Advanced Trade API, which provides real-time order updates.

  ## WebSocket Endpoints

  - User Data: `wss://advanced-trade-ws-user.coinbase.com` (JWT required)

  ## Channel Types

  - `user` - Order and account updates (authenticated)
  - `heartbeats` - Connection keepalive

  ## Authentication

  The user endpoint requires a JWT token signed with ES256 (ECDSA P-256).
  JWTs expire after 120 seconds and must be refreshed.
  """

  alias ExCoinbase.JWT

  @jwt_expiry_seconds 120
  @jwt_refresh_buffer_seconds 20

  # ============================================================================
  # Event Structs
  # ============================================================================

  defmodule UserOrderEvent do
    @moduledoc """
    Represents a user order update event from the Coinbase WebSocket.

    Events contain one or more order updates in the `events` list.
    """
    defstruct [
      :channel,
      :client_id,
      :timestamp,
      :sequence_num,
      :events
    ]

    @type t :: %__MODULE__{
            channel: String.t(),
            client_id: String.t(),
            timestamp: String.t(),
            sequence_num: integer(),
            events: [map()]
          }
  end

  defmodule OrderUpdate do
    @moduledoc """
    Represents a single order update within a UserOrderEvent.
    """
    defstruct [
      :type,
      :order_id,
      :client_order_id,
      :product_id,
      :status,
      :side,
      :order_type,
      :time_in_force,
      :created_time,
      :completion_percentage,
      :filled_size,
      :filled_value,
      :average_filled_price,
      :fee,
      :number_of_fills,
      :remaining_size,
      :outstanding_hold_amount,
      :cancel_reason
    ]

    @type t :: %__MODULE__{
            type: String.t(),
            order_id: String.t(),
            client_order_id: String.t() | nil,
            product_id: String.t(),
            status: String.t(),
            side: String.t(),
            order_type: String.t(),
            time_in_force: String.t() | nil,
            created_time: String.t() | nil,
            completion_percentage: String.t() | nil,
            filled_size: String.t() | nil,
            filled_value: String.t() | nil,
            average_filled_price: String.t() | nil,
            fee: String.t() | nil,
            number_of_fills: integer() | nil,
            remaining_size: String.t() | nil,
            outstanding_hold_amount: String.t() | nil,
            cancel_reason: String.t() | nil
          }
  end

  defmodule HeartbeatEvent do
    @moduledoc """
    Represents a heartbeat event from the Coinbase WebSocket.
    """
    defstruct [
      :channel,
      :client_id,
      :timestamp,
      :sequence_num,
      :current_time,
      :heartbeat_counter
    ]

    @type t :: %__MODULE__{
            channel: String.t(),
            client_id: String.t(),
            timestamp: String.t(),
            sequence_num: integer(),
            current_time: String.t() | nil,
            heartbeat_counter: integer() | nil
          }
  end

  # ============================================================================
  # Message Building
  # ============================================================================

  @doc """
  Builds a subscribe message for a Coinbase WebSocket channel.

  ## Parameters

    - `channel` - The channel to subscribe to ("user", "heartbeats")
    - `product_ids` - List of product IDs (e.g., ["BTC-USD", "ETH-USD"])
    - `jwt` - JWT token for authentication (required for "user" channel)

  ## Examples

      iex> build_subscribe_message("user", ["BTC-USD"], "jwt_token")
      %{"type" => "subscribe", "channel" => "user", "product_ids" => ["BTC-USD"], "jwt" => "jwt_token"}

      iex> build_subscribe_message("heartbeats", [], nil)
      %{"type" => "subscribe", "channel" => "heartbeats"}
  """
  @spec build_subscribe_message(String.t(), [String.t()], String.t() | nil) :: map()
  def build_subscribe_message(channel, product_ids, jwt) do
    message = %{
      "type" => "subscribe",
      "channel" => channel
    }

    message =
      if product_ids != [] do
        Map.put(message, "product_ids", product_ids)
      else
        message
      end

    if jwt do
      Map.put(message, "jwt", jwt)
    else
      message
    end
  end

  @doc """
  Builds an unsubscribe message for a Coinbase WebSocket channel.

  ## Examples

      iex> build_unsubscribe_message("user", ["BTC-USD"])
      %{"type" => "unsubscribe", "channel" => "user", "product_ids" => ["BTC-USD"]}
  """
  @spec build_unsubscribe_message(String.t(), [String.t()]) :: map()
  def build_unsubscribe_message(channel, product_ids) do
    %{
      "type" => "unsubscribe",
      "channel" => channel,
      "product_ids" => product_ids
    }
  end

  @doc """
  Encodes a message to JSON for sending over WebSocket.
  """
  @spec encode_message(map()) :: {:ok, String.t()} | {:error, term()}
  def encode_message(message) do
    Jason.encode(message)
  end

  @doc """
  Generates a JWT and builds a subscribe message for the user channel.

  ## Parameters

    - `api_key_id` - The API Key ID
    - `private_key_pem` - The EC Private Key in PEM format
    - `product_ids` - List of product IDs to subscribe to
  """
  @spec build_authenticated_subscribe(String.t(), String.t(), [String.t()]) ::
          {:ok, map()} | {:error, term()}
  def build_authenticated_subscribe(api_key_id, private_key_pem, product_ids) do
    with {:ok, jwt} <- JWT.generate_ws_jwt(api_key_id, private_key_pem) do
      {:ok, build_subscribe_message("user", product_ids, jwt)}
    end
  end

  # ============================================================================
  # Event Parsing
  # ============================================================================

  @doc """
  Parses a raw WebSocket message into a typed event.

  ## Returns

    - `{:ok, channel, event}` - Parsed event with channel type
    - `{:error, reason}` - If parsing fails

  ## Examples

      iex> parse_event(~s({"channel":"user","events":[...]}))
      {:ok, :user, %UserOrderEvent{...}}

      iex> parse_event(~s({"channel":"heartbeats","events":[...]}))
      {:ok, :heartbeat, %HeartbeatEvent{...}}
  """
  @spec parse_event(String.t()) :: {:ok, atom(), struct()} | {:error, term()}
  def parse_event(message) when is_binary(message) do
    case Jason.decode(message) do
      {:ok, data} ->
        parse_event_from_map(data)

      {:error, _} ->
        {:error, :invalid_json}
    end
  end

  @doc """
  Parses a decoded JSON map into a typed event.
  """
  @spec parse_event_from_map(map()) :: {:ok, atom(), struct()} | {:error, term()}
  def parse_event_from_map(%{"channel" => "user"} = data) do
    {:ok, :user, parse_user_order_event(data)}
  end

  def parse_event_from_map(%{"channel" => "heartbeats"} = data) do
    {:ok, :heartbeat, parse_heartbeat_event(data)}
  end

  def parse_event_from_map(%{"type" => "error", "message" => message}) do
    {:error, {:server_error, message}}
  end

  def parse_event_from_map(%{"type" => "error"} = data) do
    {:error, {:server_error, data["reason"] || "Unknown error"}}
  end

  def parse_event_from_map(%{"type" => "subscriptions"} = data) do
    {:ok, :subscriptions, data}
  end

  def parse_event_from_map(%{"channel" => channel}) do
    {:error, {:unknown_channel, channel}}
  end

  def parse_event_from_map(_) do
    {:error, :unknown_message_format}
  end

  @doc """
  Parses a user order event from a decoded JSON map.
  """
  @spec parse_user_order_event(map()) :: UserOrderEvent.t()
  def parse_user_order_event(data) when is_map(data) do
    %UserOrderEvent{
      channel: data["channel"],
      client_id: data["client_id"],
      timestamp: data["timestamp"],
      sequence_num: data["sequence_num"],
      events: parse_order_updates(data["events"] || [])
    }
  end

  @doc """
  Parses a list of order update events into OrderUpdate structs.
  """
  @spec parse_order_updates([map()]) :: [OrderUpdate.t()]
  def parse_order_updates(events) when is_list(events) do
    Enum.flat_map(events, &parse_order_update/1)
  end

  @doc """
  Parses a single order update event.

  Handles two event structures from Coinbase:
  - Snapshot events: `{"type": "snapshot", "orders": [...]}`
  - Update events: `{"type": "update", "order": {...}}`
  """
  @spec parse_order_update(map()) :: [OrderUpdate.t()]
  def parse_order_update(data) when is_map(data) do
    cond do
      is_list(data["orders"]) ->
        data["orders"]
        |> Enum.map(&build_order_update(data["type"], &1))

      is_map(data["order"]) ->
        [build_order_update(data["type"], data["order"])]

      true ->
        [build_order_update(data["type"], data)]
    end
  end

  defp build_order_update(type, order_data) when is_map(order_data) do
    %OrderUpdate{
      type: type,
      order_id: order_data["order_id"],
      client_order_id: order_data["client_order_id"],
      product_id: order_data["product_id"],
      status: order_data["status"],
      side: order_data["side"],
      order_type: order_data["order_type"],
      time_in_force: order_data["time_in_force"],
      created_time: order_data["created_time"],
      completion_percentage: order_data["completion_percentage"],
      filled_size: order_data["filled_size"],
      filled_value: order_data["filled_value"],
      average_filled_price: order_data["average_filled_price"],
      fee: order_data["total_fees"] || order_data["fee"],
      number_of_fills: order_data["number_of_fills"],
      remaining_size: order_data["remaining_size"],
      outstanding_hold_amount: order_data["outstanding_hold_amount"],
      cancel_reason: order_data["cancel_reason"]
    }
  end

  @doc """
  Parses a heartbeat event from a decoded JSON map.
  """
  @spec parse_heartbeat_event(map()) :: HeartbeatEvent.t()
  def parse_heartbeat_event(data) when is_map(data) do
    event_data = List.first(data["events"] || []) || %{}

    %HeartbeatEvent{
      channel: data["channel"],
      client_id: data["client_id"],
      timestamp: data["timestamp"],
      sequence_num: data["sequence_num"],
      current_time: event_data["current_time"],
      heartbeat_counter: event_data["heartbeat_counter"]
    }
  end

  # ============================================================================
  # Utility Functions
  # ============================================================================

  @doc "Returns the JWT expiry time in seconds."
  @spec jwt_expiry_seconds() :: integer()
  def jwt_expiry_seconds, do: @jwt_expiry_seconds

  @doc "Returns the JWT refresh buffer time in seconds."
  @spec jwt_refresh_buffer_seconds() :: integer()
  def jwt_refresh_buffer_seconds, do: @jwt_refresh_buffer_seconds

  @doc "Calculates the JWT refresh interval in milliseconds."
  @spec jwt_refresh_interval_ms() :: integer()
  def jwt_refresh_interval_ms do
    (@jwt_expiry_seconds - @jwt_refresh_buffer_seconds) * 1000
  end

  @doc """
  Maps Coinbase order status to lowercase format.

  ## Examples

      iex> map_order_status("FILLED")
      "filled"

      iex> map_order_status("PENDING")
      "submitted"
  """
  @spec map_order_status(String.t()) :: String.t()
  def map_order_status("FILLED"), do: "filled"
  def map_order_status("CANCELLED"), do: "cancelled"
  def map_order_status("PENDING"), do: "submitted"
  def map_order_status("OPEN"), do: "submitted"
  def map_order_status("EXPIRED"), do: "expired"
  def map_order_status("FAILED"), do: "rejected"
  def map_order_status("CANCEL_QUEUED"), do: "cancelling"
  def map_order_status(status), do: String.downcase(status)

  @doc "Returns the WebSocket URL for the user data endpoint."
  @spec websocket_user_url() :: String.t()
  def websocket_user_url do
    ExCoinbase.Client.websocket_user_url()
  end
end
