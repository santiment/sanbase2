defmodule Sanbase.SmartContracts.EthNodeClientTest do
  @moduledoc ~s"""
  Exercise the ethereumex HTTP client against a local JSON-RPC server.

  The tests do not pass any http options themselves, they rely on the ones from
  the app config, so an option name that the HTTP client does not accept fails
  here instead of only on stage/prod.
  """

  use ExUnit.Case, async: false

  alias Sanbase.SmartContracts.EthNodeClientTest.RpcServer
  alias Sanbase.SmartContracts.Utils

  @contract "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984"
  @address "0x0000000000000000000000000000000000000abc"

  setup do
    start_supervised!(
      {Plug.Cowboy, scheme: :http, plug: RpcServer, options: [port: 0, ref: RpcServer.ref()]}
    )

    original_url = Application.get_env(:ethereumex, :url)
    Application.put_env(:ethereumex, :url, "http://127.0.0.1:#{:ranch.get_port(RpcServer.ref())}")

    on_exit(fn ->
      Application.put_env(:ethereumex, :url, original_url)
      RpcServer.clear_response()
    end)

    :ok
  end

  test "eth_call reaches the node and the response is decoded" do
    RpcServer.set_response(%{"result" => uint256(1_000_000)})

    assert Utils.call_contract(@contract, "totalSupply()", [], [{:uint, 256}]) == [1_000_000]
  end

  test "batched eth_call reaches the node and the responses are decoded" do
    RpcServer.set_response(%{"result" => uint256(150)})

    address = Utils.format_address(@address)

    result =
      Utils.call_contract_batch(
        @contract,
        "balanceOf(address)",
        [[address], [address]],
        [{:uint, 256}],
        transform_args_list_fun: fn list -> list ++ ["latest"] end
      )

    assert result == [[150], [150]]
  end

  test "a JSON-RPC error is returned as an error tuple" do
    RpcServer.set_response(%{"error" => %{"code" => -32_000, "message" => "execution reverted"}})

    assert {:error, %{"message" => "execution reverted"}} =
             Utils.call_contract(@contract, "totalSupply()", [], [{:uint, 256}])
  end

  test "an unreachable node is returned as an error tuple, not raised" do
    Application.put_env(:ethereumex, :url, "http://127.0.0.1:1")

    assert {:error, %Finch.TransportError{reason: :econnrefused}} =
             Utils.call_contract(@contract, "totalSupply()", [], [{:uint, 256}])
  end

  defp uint256(value) do
    "0x" <> (value |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(64, "0"))
  end
end

defmodule Sanbase.SmartContracts.EthNodeClientTest.RpcServer do
  @moduledoc ~s"""
  Minimal Ethereum JSON-RPC server. The response returned for every request is
  set per test via `set_response/1`. The `id` of each request is echoed back, as
  ethereumex matches batch responses to requests by it.
  """

  @behaviour Plug

  import Plug.Conn

  @key {__MODULE__, :response}

  def ref(), do: __MODULE__.HTTP

  def set_response(response), do: :persistent_term.put(@key, response)

  def clear_response(), do: :persistent_term.erase(@key)

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    {:ok, body, conn} = read_body(conn)
    response = :persistent_term.get(@key)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(response_body(Jason.decode!(body), response)))
  end

  defp response_body(payload, response) when is_list(payload) do
    Enum.map(payload, fn %{"id" => id} -> response_body_for_id(response, id) end)
  end

  defp response_body(%{"id" => id}, response), do: response_body_for_id(response, id)

  defp response_body_for_id(response, id) do
    Map.merge(%{"jsonrpc" => "2.0", "id" => id}, response)
  end
end
