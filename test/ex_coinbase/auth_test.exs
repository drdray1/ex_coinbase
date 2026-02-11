defmodule ExCoinbase.AuthTest do
  use ExUnit.Case, async: true

  alias ExCoinbase.Auth
  alias ExCoinbase.Fixtures

  @stub_name ExCoinbase.AuthTest

  describe "attach/4" do
    test "registers coinbase auth options on request" do
      request = Req.new()
      attached = Auth.attach(request, "api-key", "pem-key")

      assert attached.options[:coinbase_api_key] == "api-key"
      assert attached.options[:coinbase_private_key] == "pem-key"
    end

    test "defaults sandbox to false" do
      request = Req.new()
      attached = Auth.attach(request, "api-key", "pem-key")

      assert attached.options[:coinbase_sandbox] == false
    end

    test "sets sandbox to true when specified" do
      request = Req.new()
      attached = Auth.attach(request, "api-key", "pem-key", sandbox: true)

      assert attached.options[:coinbase_sandbox] == true
    end

    test "appends coinbase_auth request step" do
      request = Req.new()
      attached = Auth.attach(request, "api-key", "pem-key")

      step_names = Enum.map(attached.request_steps, fn {name, _} -> name end)
      assert :coinbase_auth in step_names
    end
  end

  describe "request signing integration" do
    test "adds Authorization Bearer header on request" do
      test_pid = self()

      Req.Test.expect(@stub_name, fn conn ->
        auth_header = Plug.Conn.get_req_header(conn, "authorization")
        send(test_pid, {:auth_header, auth_header})
        Req.Test.json(conn, %{"accounts" => []})
      end)

      client = Fixtures.test_client(@stub_name)
      Req.get(client, url: "/accounts")

      assert_receive {:auth_header, [header]}
      assert String.starts_with?(header, "Bearer ")
    end

    test "returns jwt_generation_failed when key is invalid" do
      client =
        ExCoinbase.Client.new(
          Fixtures.sample_api_key(),
          "invalid-key",
          plug: {Req.Test, @stub_name}
        )

      result =
        client
        |> Req.get(url: "/accounts")

      assert {:ok, %Req.Response{status: 0, body: {:jwt_generation_failed, _}}} = result
    end

    test "passes through request when no credentials set" do
      test_pid = self()

      Req.Test.expect(@stub_name, fn conn ->
        auth_header = Plug.Conn.get_req_header(conn, "authorization")
        send(test_pid, {:auth_header, auth_header})
        Req.Test.json(conn, %{})
      end)

      request =
        Req.new(
          base_url: "https://api.coinbase.com/api/v3/brokerage",
          plug: {Req.Test, @stub_name}
        )
        |> Auth.attach(nil, nil)

      Req.get(request, url: "/accounts")

      assert_receive {:auth_header, []}
    end
  end
end
