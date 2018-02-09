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

    datetime1 = DateTime.from_naive!(~N[2017-05-13 15:00:00], "Etc/UTC")
    datetime2 = DateTime.from_naive!(~N[2017-05-10 16:00:00], "Etc/UTC")
    datetime3 = DateTime.from_naive!(~N[2017-05-05 17:00:00], "Etc/UTC")
    datetime4 = DateTime.from_naive!(~N[2017-05-01 18:00:00], "Etc/UTC")
    datetime5 = DateTime.from_naive!(~N[2017-04-25 19:00:00], "Etc/UTC")
    datetime6 = DateTime.from_naive!(~N[2017-04-14 20:00:00], "Etc/UTC")

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
      datetime_from: datetime6,
      datetime_mid: datetime4,
      datetime_to: datetime1
    ]
  end

  test "project total eth spent whole interval", context do
    query = """
    {
      project(id: #{context.project.id}) {
        ethSpent(from: "#{context.datetime_from}", to: "#{context.datetime_to}")
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "project"))

    trx_sum = json_response(result, 200)["data"]["project"]

    assert trx_sum == %{"ethSpent" => "20000"}
  end

  test "project total eth spent part of interval", context do
    query = """
    {
      project(id: #{context.project.id}) {
        ethSpent(from: "#{context.datetime_mid}", to: "#{context.datetime_to}")
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "project"))

    trx_sum = json_response(result, 200)["data"]["project"]

    assert trx_sum == %{"ethSpent" => "8000"}
  end
end
