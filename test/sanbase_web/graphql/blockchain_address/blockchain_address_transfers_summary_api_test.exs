defmodule SanbaseWeb.Graphql.BlockchainAddressTransfersSummaryApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)
    project = insert(:random_erc20_project)
    eth_project = insert(:random_project, slug: "ethereum")
    address = "0x00000000219ab540356cbb839cbe05303d7705fa"

    %{project: project, eth_project: eth_project, user: user, conn: conn, address: address}
  end

  test "incoming transfers summary", context do
    query = """
    {
      incomingTransfersSummary(
        address: "#{context.address}"
        slug: "#{context.project.slug}"
        from: "utc_now-10d"
        to: "utc_now"
        page: 1
        pageSize: 2
        orderBy: TRANSFERS_COUNT){
          address
          lastTransferDatetime
          transfersCount
          transactionVolume
      }
    }
    """

    rows = [
      [1_631_277_705, "0x00000000008c4fb1c916e0c88fd4cc402d935e7d", 9831.693181216842, 1],
      [1_632_097_875, "0x4a137fd5e7a256ef08a7de531a17d0be0cc7b6b6", 1799.6391336753923, 7]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        context.conn
        |> post("/graphql", query_skeleton(query))
        |> json_response(200)
        |> get_in(["data", "incomingTransfersSummary"])

      assert result == [
               %{
                 "address" => "0x00000000008c4fb1c916e0c88fd4cc402d935e7d",
                 "lastTransferDatetime" => "2021-09-10T12:41:45Z",
                 "transactionVolume" => 9831.693181216842,
                 "transfersCount" => 1
               },
               %{
                 "address" => "0x4a137fd5e7a256ef08a7de531a17d0be0cc7b6b6",
                 "lastTransferDatetime" => "2021-09-20T00:31:15Z",
                 "transactionVolume" => 1799.6391336753923,
                 "transfersCount" => 7
               }
             ]
    end)
  end

  test "transaction volume over time", context do
    # Use eth_project to force going through the EthTransfers module
    query = """
    {
      outgoingTransfersSummary(
        address: "#{context.address}"
        slug: "#{context.eth_project.slug}"
        from: "utc_now-10d"
        to: "utc_now"
        page: 1
        pageSize: 2
        orderBy: TRANSFERS_COUNT){
          address
          lastTransferDatetime
          transfersCount
          transactionVolume
      }
    }
    """

    rows = [
      [1_631_541_012, "0x9d406c4067a53f65de1a8a9273d55bfea5870a75", 9984.01432710679, 2],
      [1_632_131_211, "0x4a137fd5e7a256ef08a7de531a17d0be0cc7b6b6", 2132.223580545152, 7]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        context.conn
        |> post("/graphql", query_skeleton(query))
        |> json_response(200)
        |> get_in(["data", "outgoingTransfersSummary"])

      assert result == [
               %{
                 "address" => "0x9d406c4067a53f65de1a8a9273d55bfea5870a75",
                 "lastTransferDatetime" => "2021-09-13T13:50:12Z",
                 "transactionVolume" => 9984.01432710679,
                 "transfersCount" => 2
               },
               %{
                 "address" => "0x4a137fd5e7a256ef08a7de531a17d0be0cc7b6b6",
                 "lastTransferDatetime" => "2021-09-20T09:46:51Z",
                 "transactionVolume" => 2132.223580545152,
                 "transfersCount" => 7
               }
             ]
    end)
  end
end
