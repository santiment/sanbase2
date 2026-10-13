defmodule SanbaseWeb.Graphql.BlockchainAddressApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)
    eth_infrastructure = insert(:infrastructure, code: "ETH")

    %{
      user: user,
      conn: conn,
      eth_infrastructure: eth_infrastructure
    }
  end

  test "fetch blockchain address labels with getBlockchainAddressLabels API", context do
    rows = [["santiment/miner:v1", "Miner"], ["santiment/owner->Coinbase:v1", "owner->Coinbase"]]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        get_blockchain_address_labels(context.conn)
        |> get_in(["data", "getBlockchainAddressLabels"])

      assert result == [
               %{
                 "humanReadableName" => "Miner",
                 "name" => "santiment/miner:v1",
                 "origin" => "santiment"
               },
               %{
                 "humanReadableName" => "owner->Coinbase",
                 "name" => "santiment/owner->Coinbase:v1",
                 "origin" => "santiment"
               }
             ]
    end)
  end

  test "fetch (create) a non-existing blockchain address", context do
    Sanbase.Mock.prepare_mock2(&Sanbase.Clickhouse.Label.get_address_labels/2, {:ok, %{}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        blockchain_address(context.conn, %{
          address: "0x4efb548a2cb8f0af7c591cef21053f6875b5d38f",
          infrastructure: "ETH"
        })
        |> get_in(["data", "blockchainAddress"])

      assert result["address"] == "0x4efb548a2cb8f0af7c591cef21053f6875b5d38f"
      assert result["infrastructure"] == "ETH"
      assert result["labels"] == []
      assert result["notes"] == nil
    end)
  end

  test "fetch an existing blockchain address by id", context do
    Sanbase.Mock.prepare_mock2(&Sanbase.Clickhouse.Label.get_address_labels/2, {:ok, %{}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      address_id =
        blockchain_address(context.conn, %{
          address: "0x4efb548a2cb8f0af7c591cef21053f6875b5d38f",
          infrastructure: "ETH"
        })
        |> get_in(["data", "blockchainAddress", "id"])

      result =
        blockchain_address(context.conn, %{id: address_id})
        |> get_in(["data", "blockchainAddress"])

      # The same address if fetched and a new one is not created
      assert result["id"] == address_id

      assert result["address"] == "0x4efb548a2cb8f0af7c591cef21053f6875b5d38f"
      assert result["infrastructure"] == "ETH"
      assert result["labels"] == []
      assert result["notes"] == nil
    end)
  end

  test "fetch an existing blockchain address by address and infrastructure",
       context do
    blockchain_address =
      insert(:blockchain_address,
        address: "0x4efb548a2cb8f0af7c591cef21053f6875b5d38f",
        infrastructure: context.eth_infrastructure
      )

    Sanbase.Mock.prepare_mock2(&Sanbase.Clickhouse.Label.get_address_labels/2, {:ok, %{}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        blockchain_address(context.conn, %{
          address: "0x4efb548a2cb8f0af7c591cef21053f6875b5d38f",
          infrastructure: context.eth_infrastructure.code
        })
        |> get_in(["data", "blockchainAddress"])

      # The same address if fetched and a new one is not created
      assert result["id"] == blockchain_address.id
      assert result["address"] == "0x4efb548a2cb8f0af7c591cef21053f6875b5d38f"
      assert result["infrastructure"] == "ETH"
      assert result["labels"] == []
      assert result["notes"] == nil
    end)
  end

  defp blockchain_address(conn, selector) do
    query = """
    {
      blockchainAddress(selector: #{map_to_input_object_str(selector)}){
        id
        address
        infrastructure
        notes
        labels{ name }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end

  defp get_blockchain_address_labels(conn) do
    query = """
    {
      getBlockchainAddressLabels{
        name
        origin
        humanReadableName
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
