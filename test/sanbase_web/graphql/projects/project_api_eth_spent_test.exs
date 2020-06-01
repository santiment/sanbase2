defmodule SanbaseWeb.Graphql.ProjecApiEthSpentTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import Sanbase.TestHelpers
  import SanbaseWeb.Graphql.TestHelpers

  @eth_decimals 1_000_000_000_000_000_000

  setup do
    datetime1 = Timex.now() |> Timex.beginning_of_day()
    datetime2 = Timex.shift(datetime1, days: -10)
    datetime3 = Timex.shift(datetime1, days: -15)

    eth_infr = insert(:infrastructure, %{code: "ETH"})

    project = insert(:random_erc20_project, infrastructure: eth_infr)

    project_address = project.eth_addresses |> List.first()

    [
      project: project,
      project_address: project_address.address,
      dates_day_diff1: Timex.diff(datetime1, datetime3, :days) + 1,
      expected_sum1: 20_000,
      dates_day_diff2: Timex.diff(datetime1, datetime2, :days) + 1,
      expected_sum2: 4500,
      datetime_from: datetime3,
      datetime_to: datetime1
    ]
  end

  test "project total eth spent whole interval", context do
    rows = [
      [
        context.project_address,
        30_000 * @eth_decimals,
        10_000 * @eth_decimals,
        -20_000 * @eth_decimals
      ]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = """
      {
        project(id: #{context.project.id}) {
          ethSpent(days: #{context.dates_day_diff1})
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "project"))

      trx_sum = json_response(result, 200)["data"]["project"]

      assert trx_sum == %{"ethSpent" => context.expected_sum1}
    end)
  end

  test "project total eth spent part of interval", context do
    eth_spent = 4500

    rows = [
      [
        context.project_address,
        20_000 * @eth_decimals,
        15_500 * @eth_decimals,
        -4500 * @eth_decimals
      ]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = """
      {
        project(id: #{context.project.id}) {
          ethSpent(days: #{context.dates_day_diff2})
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "project"))

      trx_sum = json_response(result, 200)["data"]["project"]

      assert trx_sum == %{"ethSpent" => eth_spent}
    end)
  end

  test "eth spent by erc20 projects", context do
    eth_spent = 30_000

    rows = [
      [
        context.project_address,
        100_000 * @eth_decimals,
        70_000 * @eth_decimals,
        -30_000 * @eth_decimals
      ]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = """
      {
        ethSpentByErc20Projects(
          from: "#{context.datetime_from}",
          to: "#{context.datetime_to}")
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "ethSpentByErc20Projects"))

      total_eth_spent = json_response(result, 200)["data"]["ethSpentByErc20Projects"]

      assert total_eth_spent == eth_spent
    end)
  end

  test "eth spent over time by erc20 projects", context do
    [dt1, dt2, dt3, dt4, dt5] =
      generate_datetimes(Timex.shift(Timex.now(), days: -4), "1d", 5)
      |> Enum.map(&DateTime.to_unix/1)

    rows = [
      [dt1, -16_500 * @eth_decimals],
      [dt2, -5500 * @eth_decimals],
      [dt3, -3500 * @eth_decimals],
      [dt4, -2500 * @eth_decimals],
      [dt5, -500 * @eth_decimals]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = """
      {
        ethSpentOverTimeByErc20Projects(
          from: "#{context.datetime_from}",
          to: "#{context.datetime_to}",
          interval: "5d"){
            ethSpent
          }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "ethSpentOverTimeByErc20Projects"))

      total_spent = json_response(result, 200)["data"]["ethSpentOverTimeByErc20Projects"]

      assert %{"ethSpent" => 16_500.0} in total_spent
      assert %{"ethSpent" => 5500.0} in total_spent
      assert %{"ethSpent" => 3500.0} in total_spent
      assert %{"ethSpent" => 2500.0} in total_spent
      assert %{"ethSpent" => 500.0} in total_spent
    end)
  end

  # Private functions
end
