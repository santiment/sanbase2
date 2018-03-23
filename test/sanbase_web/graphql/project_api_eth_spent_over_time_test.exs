defmodule SanbaseWeb.Graphql.ProjectApiEthSpentOverTimeTest do
  use SanbaseWeb.ConnCase

  alias Sanbase.Influxdb.Measurement
  alias Sanbase.ExternalServices.Etherscan.Store
  alias Sanbase.Model.Project
  alias Sanbase.Repo

  import SanbaseWeb.Graphql.TestHelpers

  setup do
    Store.create_db()

    ticker = "TESTXYZ"
    Store.drop_measurement(ticker)

    p =
      %Project{}
      |> Project.changeset(%{name: "Santiment", ticker: ticker})
      |> Repo.insert!()

    datetime1 = DateTime.from_naive!(~N[2017-05-13 15:00:00], "Etc/UTC")
    datetime2 = DateTime.from_naive!(~N[2017-05-14 16:00:00], "Etc/UTC")
    datetime3 = DateTime.from_naive!(~N[2017-05-15 17:00:00], "Etc/UTC")
    datetime4 = DateTime.from_naive!(~N[2017-05-15 18:00:00], "Etc/UTC")
    datetime5 = DateTime.from_naive!(~N[2017-05-17 19:00:00], "Etc/UTC")
    datetime6 = DateTime.from_naive!(~N[2017-05-18 20:00:00], "Etc/UTC")

    [
      %Measurement{
        timestamp: datetime1 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 500, from_addr: "0x1", to_addr: "0x2"},
        tags: [transaction_type: "out"],
        name: ticker
      },
      %Measurement{
        timestamp: datetime2 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 1500, from_addr: "0x1", to_addr: "0x2"},
        tags: [transaction_type: "out"],
        name: ticker
      },
      %Measurement{
        timestamp: datetime3 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 2500, from_addr: "0x1", to_addr: "0x2"},
        tags: [transaction_type: "out"],
        name: ticker
      },
      %Measurement{
        timestamp: datetime4 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 3500, from_addr: "0x1", to_addr: "0x2"},
        tags: [transaction_type: "out"],
        name: ticker
      },
      %Measurement{
        timestamp: datetime4 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 100_000, from_addr: "0x2", to_addr: "0x1"},
        tags: [transaction_type: "in"],
        name: ticker
      },
      %Measurement{
        timestamp: datetime5 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 5500, from_addr: "0x1", to_addr: "0x2"},
        tags: [transaction_type: "in"],
        name: ticker
      },
      %Measurement{
        timestamp: datetime5 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 45000, from_addr: "0x2", to_addr: "0x1"},
        tags: [transaction_type: "in"],
        name: ticker
      },
      %Measurement{
        timestamp: datetime6 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 6500, from_addr: "0x1", to_addr: "0x2"},
        tags: [transaction_type: "out"],
        name: ticker
      }
    ]
    |> Store.import()

    [
      project: p,
      ticker: ticker,
      datetime_from: datetime1,
      datetime_to: datetime6
    ]
  end

  test "project eth spent over time", context do
    query = """
    {
      project(id: #{context.project.id}) {
        ethSpentOverTime(
          from: "#{context.datetime_from}",
          to: "#{context.datetime_to}",
          interval: "1d"){
            datetime,
            ethSpent
        }
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "project"))

    ethSpentOverTime = json_response(result, 200)["data"]["project"]["ethSpentOverTime"]

    assert length(ethSpentOverTime) == 6

    assert %{
             "datetime" => "2017-05-13T00:00:00Z",
             "ethSpent" => 500
           } in ethSpentOverTime

    assert %{
             "datetime" => "2017-05-14T00:00:00Z",
             "ethSpent" => 1500
           } in ethSpentOverTime

    assert %{
             "datetime" => "2017-05-15T00:00:00Z",
             "ethSpent" => 6000
           } in ethSpentOverTime

    assert %{
             "datetime" => "2017-05-16T00:00:00Z",
             "ethSpent" => 0
           } in ethSpentOverTime

    assert %{
             "datetime" => "2017-05-17T00:00:00Z",
             "ethSpent" => 0
           } in ethSpentOverTime

    assert %{
             "datetime" => "2017-05-18T00:00:00Z",
             "ethSpent" => 6500
           } in ethSpentOverTime
  end
end
