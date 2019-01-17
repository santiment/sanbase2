defmodule SanbaseWeb.Graphql.ProjecApiEthSpentTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.Model.{Project, Infrastructure, ProjectEthAddress}
  alias Sanbase.Repo

  import SanbaseWeb.Graphql.TestHelpers
  import Mock

  setup do
    datetime1 = Timex.now() |> Timex.beginning_of_day()
    datetime2 = Timex.shift(datetime1, days: -10)
    datetime3 = Timex.shift(datetime1, days: -15)

    eth_infrastructure =
      %Infrastructure{code: "ETH"}
      |> Repo.insert!()

    p =
      %Project{}
      |> Project.changeset(%{
        name: "Santiment",
        ticker: "SAN",
        coinmarketcap_id: "santiment",
        main_contract_address: "0x123123",
        infrastructure_id: eth_infrastructure.id
      })
      |> Repo.insert!()

    project_address = "0x12345"

    %ProjectEthAddress{}
    |> ProjectEthAddress.changeset(%{
      project_id: p.id,
      address: project_address
    })
    |> Repo.insert_or_update()

    [
      project: p,
      project_address: project_address,
      dates_day_diff1: Timex.diff(datetime1, datetime3, :days) + 1,
      expected_sum1: 20000,
      dates_day_diff2: Timex.diff(datetime1, datetime2, :days) + 1,
      expected_sum2: 4500,
      datetime_from: datetime3,
      datetime_to: datetime1
    ]
  end

  test "project total eth spent whole interval", context do
    with_mock Sanbase.Clickhouse.EthTransfers,
      eth_spent: fn _, _, _ ->
        {:ok, 20_000}
      end do
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
    end
  end

  test "project total eth spent part of interval", context do
    eth_spent = 4500

    with_mock Sanbase.Clickhouse.EthTransfers,
      eth_spent: fn _, _, _ ->
        {:ok, eth_spent}
      end do
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
    end
  end

  test "eth spent by erc20 projects", context do
    eth_spent = 30_000

    with_mock Sanbase.Clickhouse.EthTransfers,
      eth_spent: fn _, _, _ ->
        {:ok, eth_spent}
      end do
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
    end
  end

  test "eth spent over time by erc20 projects", context do
    with_mock Sanbase.Clickhouse.EthTransfers, [:passthrough],
      eth_spent_over_time: fn _, _, _, _ ->
        {:ok,
         [
           %{datetime: Timex.now(), eth_spent: 16500},
           %{datetime: Timex.shift(Timex.now(), days: -1), eth_spent: 5500},
           %{datetime: Timex.shift(Timex.now(), days: -2), eth_spent: 3500},
           %{datetime: Timex.shift(Timex.now(), days: -3), eth_spent: 2500},
           %{datetime: Timex.shift(Timex.now(), days: -4), eth_spent: 500}
         ]}
      end do
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

      assert %{"ethSpent" => 16500} in total_spent
      assert %{"ethSpent" => 5500} in total_spent
      assert %{"ethSpent" => 3500} in total_spent
      assert %{"ethSpent" => 2500} in total_spent
      assert %{"ethSpent" => 500} in total_spent
    end
  end

  # Private functions
end
