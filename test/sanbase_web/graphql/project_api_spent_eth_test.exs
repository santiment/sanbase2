defmodule SanbaseWeb.Graphql.ProjecApiEthSpentTest do
  use SanbaseWeb.ConnCase

  alias Sanbase.Influxdb.Measurement
  alias Sanbase.ExternalServices.Etherscan.Store
  alias Sanbase.Model.Project
  alias Sanbase.Repo

  import SanbaseWeb.Graphql.TestHelpers

  setup do
    Store.create_db()

    ticker = "SAN"
    ticker2 = "TESTTEST"
    ticker3 = "XYZ"
    Store.drop_measurement(ticker)

    p =
      %Project{}
      |> Project.changeset(%{name: "Santiment", ticker: ticker})
      |> Repo.insert!()

    today = Timex.now()
    datetime1 = today
    datetime2 = Timex.shift(today, days: -5)
    datetime3 = Timex.shift(today, days: -10)
    datetime4 = Timex.shift(today, days: -15)
    datetime5 = Timex.shift(today, days: -20)
    datetime6 = Timex.shift(today, days: -25)

    [
      %Measurement{
        timestamp: datetime1 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 500},
        tags: [transaction_type: "out"],
        name: ticker
      },
      %Measurement{
        timestamp: datetime2 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 1500},
        tags: [transaction_type: "out"],
        name: ticker
      },
      %Measurement{
        timestamp: datetime3 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 2500},
        tags: [transaction_type: "out"],
        name: ticker
      },
      %Measurement{
        timestamp: datetime4 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 3500},
        tags: [transaction_type: "out"],
        name: ticker
      },
      %Measurement{
        timestamp: datetime4 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 100_000},
        tags: [transaction_type: "in"],
        name: ticker
      },
      %Measurement{
        timestamp: datetime5 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 5500},
        tags: [transaction_type: "out"],
        name: ticker
      },
      %Measurement{
        timestamp: datetime6 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 6500},
        tags: [transaction_type: "out"],
        name: ticker
      },
      %Measurement{
        timestamp: datetime6 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 5000},
        tags: [transaction_type: "out"],
        name: ticker2
      },
      %Measurement{
        timestamp: datetime6 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 5000},
        tags: [transaction_type: "out"],
        name: ticker3
      }
    ]
    |> Store.import()

    [
      project: p,
      ticker: ticker,
      dates_day_diff1: Timex.diff(datetime1, datetime6, :days) + 1,
      expected_sum1: 20000,
      dates_day_diff2: Timex.diff(datetime1, datetime3, :days) + 1,
      expected_sum2: 4500,
      expected_total_sum: 30000,
      datetime_from: datetime6,
      datetime_to: datetime1
    ]
  end

  test "project total eth spent whole interval", context do
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

  test "project total eth spent part of interval", context do
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

    assert trx_sum == %{"ethSpent" => context.expected_sum2}
  end

  test "eth spent by all projects", context do
    query = """
    {
      ethSpentByAllProjects(from: "#{context.datetime_from}", to: "#{context.datetime_to}")
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "ethSpentByAllProjects"))

    total_trx_sum = json_response(result, 200)["data"]["ethSpentByAllProjects"]

    assert total_trx_sum == context.expected_total_sum
  end
end
