defmodule SanbaseWeb.Graphql.ProjectApiEthSpentOverTimeTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.Influxdb.Measurement
  alias Sanbase.ExternalServices.Etherscan.Store

  alias Sanbase.Model.{
    Project,
    ProjectEthAddress
  }

  alias Sanbase.Repo

  import SanbaseWeb.Graphql.TestHelpers

  setup do
    Store.create_db()

    ticker = "TESTXYZ"
    Store.drop_measurement(ticker)

    p =
      %Project{}
      |> Project.changeset(%{name: "Santiment", ticker: ticker, coinmarketcap_id: "santiment"})
      |> Repo.insert!()

    project_address1 = "0x123a12345bc"

    %ProjectEthAddress{}
    |> ProjectEthAddress.changeset(%{
      project_id: p.id,
      address: project_address1
    })
    |> Repo.insert_or_update()

    project_address2 = "0x321321321"

    %ProjectEthAddress{}
    |> ProjectEthAddress.changeset(%{
      project_id: p.id,
      address: project_address2
    })
    |> Repo.insert!()

    datetime1 = DateTime.from_naive!(~N[2017-05-13 15:00:00], "Etc/UTC")
    datetime2 = DateTime.from_naive!(~N[2017-05-14 16:00:00], "Etc/UTC")
    datetime2_internal = DateTime.from_naive!(~N[2017-05-14 17:00:00], "Etc/UTC")
    datetime3 = DateTime.from_naive!(~N[2017-05-15 17:00:00], "Etc/UTC")
    datetime4 = DateTime.from_naive!(~N[2017-05-15 18:00:00], "Etc/UTC")
    datetime4_internal = DateTime.from_naive!(~N[2017-05-15 19:00:00], "Etc/UTC")
    datetime5 = DateTime.from_naive!(~N[2017-05-17 19:00:00], "Etc/UTC")
    datetime6 = DateTime.from_naive!(~N[2017-05-18 20:00:00], "Etc/UTC")

    [
      %Measurement{
        timestamp: datetime1 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 500, from_addr: "0x1", to_addr: "0x2", trx_hash: "0x321"},
        tags: [transaction_type: "out"],
        name: ticker
      },
      %Measurement{
        timestamp: datetime2 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 1500, from_addr: "0x1", to_addr: "0x2", trx_hash: "0x321a"},
        tags: [transaction_type: "out"],
        name: ticker
      },
      %Measurement{
        timestamp: datetime2_internal |> DateTime.to_unix(:nanoseconds),
        fields: %{
          trx_value: 50000,
          from_addr: project_address1,
          to_addr: project_address2,
          trx_hash: "0x321a_Int"
        },
        tags: [transaction_type: "out"],
        name: ticker
      },
      %Measurement{
        timestamp: datetime2_internal |> DateTime.to_unix(:nanoseconds),
        fields: %{
          trx_value: 50000,
          from_addr: project_address2,
          to_addr: project_address1,
          trx_hash: "0x321a_Int"
        },
        tags: [transaction_type: "in"],
        name: ticker
      },
      %Measurement{
        timestamp: datetime3 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 2500, from_addr: "0x1", to_addr: "0x2", trx_hash: "0x321b"},
        tags: [transaction_type: "out"],
        name: ticker
      },
      %Measurement{
        timestamp: datetime4 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 3500, from_addr: "0x1", to_addr: "0x2", trx_hash: "0x321c"},
        tags: [transaction_type: "out"],
        name: ticker
      },
      %Measurement{
        timestamp: datetime4 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 100_000, from_addr: "0x2", to_addr: "0x1", trx_hash: "0x321d"},
        tags: [transaction_type: "in"],
        name: ticker
      },
      %Measurement{
        timestamp: datetime4_internal |> DateTime.to_unix(:nanoseconds),
        fields: %{
          trx_value: 16_670,
          from_addr: project_address1,
          to_addr: project_address2,
          trx_hash: "0x321d_Int"
        },
        tags: [transaction_type: "in"],
        name: ticker
      },
      %Measurement{
        timestamp: datetime4_internal |> DateTime.to_unix(:nanoseconds),
        fields: %{
          trx_value: 16_670,
          from_addr: project_address2,
          to_addr: project_address1,
          trx_hash: "0x321d_Int"
        },
        tags: [transaction_type: "out"],
        name: ticker
      },
      %Measurement{
        timestamp: datetime5 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 5500, from_addr: "0x1", to_addr: "0x2", trx_hash: "0x321e"},
        tags: [transaction_type: "in"],
        name: ticker
      },
      %Measurement{
        timestamp: datetime5 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 45000, from_addr: "0x2", to_addr: "0x1", trx_hash: "0x321f"},
        tags: [transaction_type: "in"],
        name: ticker
      },
      %Measurement{
        timestamp: datetime6 |> DateTime.to_unix(:nanoseconds),
        fields: %{trx_value: 6500, from_addr: "0x1", to_addr: "0x2", trx_hash: "0x321g"},
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
