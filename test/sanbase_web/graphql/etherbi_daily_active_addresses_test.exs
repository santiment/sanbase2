defmodule Sanbase.Etherbi.DailyActiveAddressesApiTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Etherbi.DailyActiveAddresses.Store
  alias Sanbase.Model.{Project, Ico}
  alias Sanbase.Repo

  import SanbaseWeb.Graphql.TestHelpers

  setup do
    Store.create_db()

    ticker = "SAN"
    slug = "santiment"
    contract_address = "0x1234"
    Store.drop_measurement(contract_address)

    project =
      %Project{
        name: "Santiment",
        ticker: ticker,
        coinmarketcap_id: slug,
        main_contract_address: contract_address
      }
      |> Repo.insert!()

    %Ico{project_id: project.id}
    |> Repo.insert!()

    datetime1 = DateTime.from_naive!(~N[2017-05-13 21:45:00], "Etc/UTC")
    datetime2 = DateTime.from_naive!(~N[2017-05-14 21:55:00], "Etc/UTC")
    datetime3 = DateTime.from_naive!(~N[2017-05-15 22:05:00], "Etc/UTC")
    datetime4 = DateTime.from_naive!(~N[2017-05-16 22:15:00], "Etc/UTC")
    datetime5 = DateTime.from_naive!(~N[2017-05-17 22:25:00], "Etc/UTC")
    datetime6 = DateTime.from_naive!(~N[2017-05-18 22:35:00], "Etc/UTC")
    datetime7 = DateTime.from_naive!(~N[2017-05-19 22:45:00], "Etc/UTC")
    datetime8 = DateTime.from_naive!(~N[2017-05-20 22:55:00], "Etc/UTC")

    Store.import([
      %Measurement{
        timestamp: datetime1 |> DateTime.to_unix(:nanoseconds),
        fields: %{active_addresses: 5000},
        tags: [],
        name: contract_address
      },
      %Measurement{
        timestamp: datetime2 |> DateTime.to_unix(:nanoseconds),
        fields: %{active_addresses: 1000},
        tags: [],
        name: contract_address
      },
      %Measurement{
        timestamp: datetime3 |> DateTime.to_unix(:nanoseconds),
        fields: %{active_addresses: 500},
        tags: [],
        name: contract_address
      },
      %Measurement{
        timestamp: datetime4 |> DateTime.to_unix(:nanoseconds),
        fields: %{active_addresses: 15000},
        tags: [],
        name: contract_address
      },
      %Measurement{
        timestamp: datetime5 |> DateTime.to_unix(:nanoseconds),
        fields: %{active_addresses: 65000},
        tags: [],
        name: contract_address
      },
      %Measurement{
        timestamp: datetime6 |> DateTime.to_unix(:nanoseconds),
        fields: %{active_addresses: 50},
        tags: [],
        name: contract_address
      },
      %Measurement{
        timestamp: datetime7 |> DateTime.to_unix(:nanoseconds),
        fields: %{active_addresses: 5},
        tags: [],
        name: contract_address
      },
      %Measurement{
        timestamp: datetime8 |> DateTime.to_unix(:nanoseconds),
        fields: %{active_addresses: 5000},
        tags: [],
        name: contract_address
      }
    ])

    [
      slug: slug,
      datetime1: datetime1,
      datetime2: datetime2,
      datetime3: datetime3,
      datetime4: datetime4,
      datetime5: datetime5,
      datetime6: datetime6,
      datetime7: datetime7,
      datetime8: datetime8
    ]
  end

  test "fetch daily active addresses no interval provided", context do
    query = """
    {
      dailyActiveAddresses(
        slug: "#{context.slug}",
        from: "#{context.datetime1}",
        to: "#{context.datetime8}") {
          datetime
          activeAddresses
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "dailyActiveAddresses"))

    active_addresses = json_response(result, 200)["data"]["dailyActiveAddresses"]

    assert Enum.find(active_addresses, fn %{"activeAddresses" => activeAddresses} ->
             activeAddresses == 5000
           end)
  end

  test "fetch daily active addresses no aggregation", context do
    query = """
    {
      dailyActiveAddresses(
        slug: "#{context.slug}",
        from: "#{context.datetime1}",
        to: "#{context.datetime8}",
        interval: "1d") {
          datetime
          activeAddresses
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "dailyActiveAddresses"))

    active_addresses = json_response(result, 200)["data"]["dailyActiveAddresses"]

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime1),
             "activeAddresses" => 5000
           } in active_addresses

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime2),
             "activeAddresses" => 1000
           } in active_addresses

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime3),
             "activeAddresses" => 500
           } in active_addresses

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime4),
             "activeAddresses" => 15000
           } in active_addresses

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime5),
             "activeAddresses" => 65000
           } in active_addresses

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime6),
             "activeAddresses" => 50
           } in active_addresses

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime7),
             "activeAddresses" => 5
           } in active_addresses

    assert %{
             "datetime" => DateTime.to_iso8601(context.datetime8),
             "activeAddresses" => 5000
           } in active_addresses
  end

  test "fetch daily active addreses with aggregation - average for all the days in the interval",
       context do
    query = """
    {
      dailyActiveAddresses(
        slug: "#{context.slug}",
        from: "#{context.datetime1}",
        to: "#{context.datetime8}",
        interval: "2d") {
          datetime
          activeAddresses
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "dailyActiveAddresses"))

    active_addresses = json_response(result, 200)["data"]["dailyActiveAddresses"]

    assert %{
             "datetime" => "2017-05-12T00:00:00Z",
             "activeAddresses" => 5000
           } in active_addresses

    assert %{
             "datetime" => "2017-05-14T00:00:00Z",
             "activeAddresses" => 750
           } in active_addresses

    assert %{
             "datetime" => "2017-05-16T00:00:00Z",
             "activeAddresses" => 40000
           } in active_addresses

    assert %{
             "datetime" => "2017-05-18T00:00:00Z",
             "activeAddresses" => 28
           } in active_addresses

    assert %{
             "datetime" => "2017-05-20T00:00:00Z",
             "activeAddresses" => 5000
           } in active_addresses
  end

  test "no data returned for daily active addresses", context do
    from_no_data = Timex.shift(context.datetime1, days: -10)
    to_no_data = Timex.shift(context.datetime1, days: -2)

    query = """
    {
      dailyActiveAddresses(
        slug: "#{context.slug}",
        from: "#{from_no_data}",
        to: "#{to_no_data}",
        interval: "2d") {
          datetime
          activeAddresses
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "dailyActiveAddresses"))

    active_addresses = json_response(result, 200)["data"]["dailyActiveAddresses"]

    assert active_addresses == []
  end

  test "fetch average daily active addreses", context do
    query = """
    {
      projectBySlug(slug: "santiment") {
        averageDailyActiveAddresses(
          from: "#{context.datetime1}",
          to: "#{context.datetime8}")
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "projectBySlug"))

    active_addresses =
      json_response(result, 200)["data"]["projectBySlug"]["averageDailyActiveAddresses"]

    assert active_addresses == 11444
  end

  test "fetch average daily active addreses returns 0 if there is no activity", context do
    query = """
    {
      projectBySlug(slug: "santiment") {
        averageDailyActiveAddresses(
          from: "2018-03-17T18:47:00.000000Z",
          to: "2018-04-12T18:47:00.000000Z")
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "projectBySlug"))

    active_addresses =
      json_response(result, 200)["data"]["projectBySlug"]["averageDailyActiveAddresses"]

    assert active_addresses == 0
  end
end
