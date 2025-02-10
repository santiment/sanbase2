defmodule SanbaseWeb.Graphql.ProjecApiEthSpentTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import Sanbase.TestHelpers
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    datetime1 = Timex.beginning_of_day(DateTime.utc_now())
    datetime2 = Timex.shift(datetime1, days: -10)
    datetime3 = Timex.shift(datetime1, days: -15)

    eth_infr = insert(:infrastructure, %{code: "ETH"})

    project = insert(:random_erc20_project, infrastructure: eth_infr)

    project_address = List.first(project.eth_addresses)

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
        30_000,
        10_000,
        -20_000
      ]
    ]

    (&Sanbase.ClickhouseRepo.query/2)
    |> Sanbase.Mock.prepare_mock2({:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = """
      {
        project(id: #{context.project.id}) {
          ethSpent(days: #{context.dates_day_diff1})
        }
      }
      """

      result = post(context.conn, "/graphql", query_skeleton(query, "project"))

      trx_sum = json_response(result, 200)["data"]["project"]

      assert trx_sum == %{"ethSpent" => context.expected_sum1}
    end)
  end

  test "project total eth spent part of interval", context do
    eth_spent = 4500

    rows = [
      [
        context.project_address,
        20_000,
        15_500,
        -4500
      ]
    ]

    (&Sanbase.ClickhouseRepo.query/2)
    |> Sanbase.Mock.prepare_mock2({:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = """
      {
        project(id: #{context.project.id}) {
          ethSpent(days: #{context.dates_day_diff2})
        }
      }
      """

      result = post(context.conn, "/graphql", query_skeleton(query, "project"))

      trx_sum = json_response(result, 200)["data"]["project"]

      assert trx_sum == %{"ethSpent" => eth_spent}
    end)
  end

  test "eth spent by erc20 projects", context do
    eth_spent = 30_000

    rows = [
      [
        context.project_address,
        100_000,
        70_000,
        -30_000
      ]
    ]

    (&Sanbase.ClickhouseRepo.query/2)
    |> Sanbase.Mock.prepare_mock2({:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = """
      {
        ethSpentByErc20Projects(
          from: "#{context.datetime_from}",
          to: "#{context.datetime_to}")
      }
      """

      result = post(context.conn, "/graphql", query_skeleton(query, "ethSpentByErc20Projects"))

      total_eth_spent = json_response(result, 200)["data"]["ethSpentByErc20Projects"]

      assert total_eth_spent == eth_spent
    end)
  end

  test "eth spent over time by erc20 projects", context do
    [dt0, dt1, dt2, dt3, dt4, dt5] =
      DateTime.utc_now()
      |> Timex.shift(days: -5)
      |> generate_datetimes("1d", 6)
      |> Enum.map(&DateTime.to_unix/1)

    # Historical Balances Changes uses internally the historical balances query,
    # so that's what needs to be mocked
    rows = [
      [dt0, 50_000, 1],
      [dt1, 33_500, 1],
      [dt2, 28_000, 1],
      [dt3, 24_500, 1],
      [dt4, 22_000, 1],
      [dt5, 21_500, 1]
    ]

    (&Sanbase.ClickhouseRepo.query/2)
    |> Sanbase.Mock.prepare_mock2({:ok, %{rows: rows}})
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

      result = post(context.conn, "/graphql", query_skeleton(query, "ethSpentOverTimeByErc20Projects"))

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
