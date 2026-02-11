defmodule ExCoinbase.WebSocket.ClientTest do
  use ExUnit.Case, async: false
  use Mimic

  alias ExCoinbase.WebSocket.Client
  alias ExCoinbase.WebSocket.Client.State

  setup :verify_on_exit!

  describe "start_link/3" do
    test "calls WebSockex.start_link with correct arguments" do
      expect(WebSockex, :start_link, fn url, module, state, opts ->
        assert url == "wss://test.example.com"
        assert module == Client
        assert %State{parent_pid: _, connected: false} = state
        assert opts[:handle_initial_conn_failure] == true
        {:ok, spawn(fn -> Process.sleep(:infinity) end)}
      end)

      assert {:ok, _pid} = Client.start_link("wss://test.example.com", self())
    end

    test "removes :name from websockex_opts" do
      expect(WebSockex, :start_link, fn _url, _module, _state, opts ->
        refute Keyword.has_key?(opts, :name)
        {:ok, spawn(fn -> Process.sleep(:infinity) end)}
      end)

      Client.start_link("wss://test.example.com", self(), name: :test_ws)
    end
  end

  describe "send_message/2" do
    test "encodes map to JSON and sends text frame" do
      pid = spawn(fn -> Process.sleep(:infinity) end)

      expect(WebSockex, :send_frame, fn ^pid, {:text, json} ->
        decoded = Jason.decode!(json)
        assert decoded["type"] == "subscribe"
        :ok
      end)

      assert :ok = Client.send_message(pid, %{"type" => "subscribe"})
    end
  end

  describe "send_text/2" do
    test "sends raw text frame" do
      pid = spawn(fn -> Process.sleep(:infinity) end)

      expect(WebSockex, :send_frame, fn ^pid, {:text, "raw text"} ->
        :ok
      end)

      assert :ok = Client.send_text(pid, "raw text")
    end
  end

  describe "close/1" do
    test "sends close cast" do
      pid = spawn(fn -> Process.sleep(:infinity) end)

      expect(WebSockex, :cast, fn ^pid, :close ->
        :ok
      end)

      assert :ok = Client.close(pid)
    end
  end

  # ============================================================================
  # Callback Tests (direct invocation)
  # ============================================================================

  describe "handle_connect/2" do
    test "sends {:stream_connected, pid} to parent" do
      state = %State{parent_pid: self(), connected: false}
      {:ok, new_state} = Client.handle_connect(%{}, state)

      assert_receive {:stream_connected, _pid}
      assert new_state.connected == true
    end
  end

  describe "handle_frame/2" do
    test "text frame sends {:stream_message, pid, msg} to parent" do
      state = %State{parent_pid: self(), connected: true}
      {:ok, ^state} = Client.handle_frame({:text, "hello"}, state)

      assert_receive {:stream_message, _pid, "hello"}
    end

    test "binary frame sends {:stream_binary, pid, msg} to parent" do
      state = %State{parent_pid: self(), connected: true}
      {:ok, ^state} = Client.handle_frame({:binary, <<1, 2, 3>>}, state)

      assert_receive {:stream_binary, _pid, <<1, 2, 3>>}
    end

    test "ping frame replies with pong" do
      state = %State{parent_pid: self(), connected: true}
      {:reply, {:pong, "ping_data"}, ^state} = Client.handle_frame({:ping, "ping_data"}, state)
    end

    test "pong frame returns ok" do
      state = %State{parent_pid: self(), connected: true}
      {:ok, ^state} = Client.handle_frame({:pong, ""}, state)
    end
  end

  describe "handle_disconnect/2" do
    test "sends {:stream_disconnected, pid, reason} to parent" do
      state = %State{parent_pid: self(), connected: true}
      {:ok, new_state} = Client.handle_disconnect(%{reason: :closed}, state)

      assert_receive {:stream_disconnected, _pid, :closed}
      assert new_state.connected == false
    end

    test "uses :unknown when reason is missing" do
      state = %State{parent_pid: self(), connected: true}
      {:ok, _new_state} = Client.handle_disconnect(%{}, state)

      assert_receive {:stream_disconnected, _pid, :unknown}
    end
  end

  describe "handle_cast/2" do
    test ":close returns close tuple" do
      state = %State{parent_pid: self(), connected: true}
      {:close, ^state} = Client.handle_cast(:close, state)
    end

    test "{:send, frame} replies with frame" do
      state = %State{parent_pid: self(), connected: true}
      frame = {:text, "test"}
      {:reply, ^frame, ^state} = Client.handle_cast({:send, frame}, state)
    end
  end
end
