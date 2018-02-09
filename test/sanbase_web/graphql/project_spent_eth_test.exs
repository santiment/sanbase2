defmodule SanbaseWeb.Graphql.ProjectSpentEthTest do
  use SanbaseWeb.ConnCase

  alias Sanbase.Influxdb.Measurement
  alias Sanbase.ExternalServices.Etherscan.Store
  alias Sanbase.Model.Project
  alias Sanbase.Repo

  import SanbaseWeb.Graphql.TestHelpers

  setup do
    Store.create_db()

    name = "santiment"
    Store.drop_measurement(name)

    p =
      %Project{}
      |> Project.changeset(%{name: "Santiment", coinmarketcap_id: name})
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
        name: name
      },
      %Measurement{
        timestamp: datetime2 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 1500},
        tags: [transaction_type: "out"],
        name: name
      },
      %Measurement{
        timestamp: datetime3 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 2500},
        tags: [transaction_type: "out"],
        name: name
      },
      %Measurement{
        timestamp: datetime4 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 3500},
        tags: [transaction_type: "out"],
        name: name
      },
      %Measurement{
        timestamp: datetime4 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 100_000},
        tags: [transaction_type: "in"],
        name: name
      },
      %Measurement{
        timestamp: datetime5 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 5500},
        tags: [transaction_type: "out"],
        name: name
      },
      %Measurement{
        timestamp: datetime6 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 6500},
        tags: [transaction_type: "out"],
        name: name
      }
    ]
    |> Store.import()

    [
      project: p,
      name: name,
      dates_day_diff1: Timex.diff(datetime1, datetime6, :days) + 1,
      expected_sum1: 20000,
      dates_day_diff2: Timex.diff(datetime1, datetime3, :days) + 1,
      expected_sum2: 4500
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
end
