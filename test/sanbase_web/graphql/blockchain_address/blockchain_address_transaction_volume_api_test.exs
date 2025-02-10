defmodule SanbaseWeb.Graphql.BlockchainAddressTransactionVolumeApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)
    project = insert(:random_erc20_project)

    %{project: project, user: user, conn: conn}
  end

  test "transaction volume per address", context do
    query = """
    {
      transactionVolumePerAddress(
        addresses: [ "0x0608b496a97806c9020c4f45ca1e7d16fe39b7a6", "0x8cae5b15cc4f80ca9d3248aa5b138f0a2ef043fc" ]
        selector: {slug: "#{context.project.slug}"}
        from: "utc_now-2d"
        to: "utc_now"){
          address
          transactionVolumeTotal
          transactionVolumeInflow
          transactionVolumeOutflow
        }
    }
    """

    rows = [
      ["0x8cae5b15cc4f80ca9d3248aa5b138f0a2ef043fc", 662.9295609999999, 662.9295609999999],
      ["0x0608b496a97806c9020c4f45ca1e7d16fe39b7a6", 712.036324, 712.036324]
    ]

    (&Sanbase.ClickhouseRepo.query/2)
    |> Sanbase.Mock.prepare_mock2({:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        context.conn
        |> post("/graphql", query_skeleton(query))
        |> json_response(200)
        |> get_in(["data", "transactionVolumePerAddress"])

      assert result == [
               %{
                 "address" => "0x0608b496a97806c9020c4f45ca1e7d16fe39b7a6",
                 "transactionVolumeInflow" => 712.036324,
                 "transactionVolumeOutflow" => 712.036324,
                 "transactionVolumeTotal" => 1424.072648
               },
               %{
                 "address" => "0x8cae5b15cc4f80ca9d3248aa5b138f0a2ef043fc",
                 "transactionVolumeInflow" => 662.9295609999999,
                 "transactionVolumeOutflow" => 662.9295609999999,
                 "transactionVolumeTotal" => 1325.8591219999998
               }
             ]
    end)
  end

  test "transaction volume over time", context do
    query = """
    {
      blockchainAddressTransactionVolumeOverTime(
        addresses: ["0x00000000219ab540356cbb839cbe05303d7705fa"]
        selector: {slug: "#{context.project.slug}"}
        from: "utc_now-2d"
        to: "utc_now"
        interval:"1d"){
          datetime
          transactionVolumeTotal
          transactionVolumeInflow
          transactionVolumeOutflow
        }
    }
    """

    rows = [
      [1_631_664_000, 9216.0, 11.04],
      [1_631_750_400, 8832.0, 502.12],
      [1_631_836_800, 1568.0, 820.55]
    ]

    (&Sanbase.ClickhouseRepo.query/2)
    |> Sanbase.Mock.prepare_mock2({:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        context.conn
        |> post("/graphql", query_skeleton(query))
        |> json_response(200)
        |> get_in(["data", "blockchainAddressTransactionVolumeOverTime"])

      assert result == [
               %{
                 "datetime" => "2021-09-15T00:00:00Z",
                 "transactionVolumeInflow" => 9216.0,
                 "transactionVolumeOutflow" => 11.04,
                 "transactionVolumeTotal" => 9227.04
               },
               %{
                 "datetime" => "2021-09-16T00:00:00Z",
                 "transactionVolumeInflow" => 8832.0,
                 "transactionVolumeOutflow" => 502.12,
                 "transactionVolumeTotal" => 9334.12
               },
               %{
                 "datetime" => "2021-09-17T00:00:00Z",
                 "transactionVolumeInflow" => 1568.0,
                 "transactionVolumeOutflow" => 820.55,
                 "transactionVolumeTotal" => 2388.55
               }
             ]
    end)
  end
end
