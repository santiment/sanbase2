defmodule Sanbase.Etherbi.DailyActiveAddressesApiTest do
  use SanbaseWeb.ConnCase, async: false
  @moduletag checkout_repo: [Sanbase.Repo, Sanbase.TimescaleRepo]
  @moduletag timescaledb: true

  alias Sanbase.Model.Project
  alias Sanbase.Repo

  import SanbaseWeb.Graphql.TestHelpers

  require Sanbase.Factory
  import Sanbase.TimescaleFactory

  setup do
    staked_user = Sanbase.Factory.insert(:staked_user)
    conn = setup_jwt_auth(build_conn(), staked_user)

    ticker = "SAN"
    slug = "santiment"
    contract_address = "0x1234"

    %Project{
      name: "Santiment",
      ticker: ticker,
      coinmarketcap_id: slug,
      main_contract_address: contract_address
    }
    |> Repo.insert!()

    datetime1 = DateTime.from_naive!(~N[2017-05-13 00:00:00], "Etc/UTC")
    datetime2 = DateTime.from_naive!(~N[2017-05-14 00:00:00], "Etc/UTC")
    datetime3 = DateTime.from_naive!(~N[2017-05-15 00:00:00], "Etc/UTC")
    datetime4 = DateTime.from_naive!(~N[2017-05-16 00:00:00], "Etc/UTC")
    datetime5 = DateTime.from_naive!(~N[2017-05-17 00:00:00], "Etc/UTC")
    datetime6 = DateTime.from_naive!(~N[2017-05-18 00:00:00], "Etc/UTC")
    datetime7 = DateTime.from_naive!(~N[2017-05-19 00:00:00], "Etc/UTC")
    datetime8 = DateTime.from_naive!(~N[2017-05-20 00:00:00], "Etc/UTC")
    datetime9 = DateTime.from_naive!(~N[2017-05-23 00:00:00], "Etc/UTC")

    insert(:daily_active_addresses, %{
      contract_address: contract_address,
      timestamp: datetime1,
      active_addresses: 5000
    })

    insert(:daily_active_addresses, %{
      contract_address: contract_address,
      timestamp: datetime2,
      active_addresses: 100
    })

    insert(:daily_active_addresses, %{
      contract_address: contract_address,
      timestamp: datetime3,
      active_addresses: 500
    })

    insert(:daily_active_addresses, %{
      contract_address: contract_address,
      timestamp: datetime4,
      active_addresses: 15000
    })

    insert(:daily_active_addresses, %{
      contract_address: contract_address,
      timestamp: datetime5,
      active_addresses: 65000
    })

    insert(:daily_active_addresses, %{
      contract_address: contract_address,
      timestamp: datetime6,
      active_addresses: 50
    })

    insert(:daily_active_addresses, %{
      contract_address: contract_address,
      timestamp: datetime7,
      active_addresses: 5
    })

    insert(:daily_active_addresses, %{
      contract_address: contract_address,
      timestamp: datetime8,
      active_addresses: 0
    })

    insert(:daily_active_addresses, %{
      contract_address: contract_address,
      timestamp: datetime9,
      active_addresses: 100
    })

    [
      slug: slug,
      datetime1: datetime1,
      datetime2: datetime2,
      datetime3: datetime3,
      datetime4: datetime4,
      datetime5: datetime5,
      datetime6: datetime6,
      datetime7: datetime7,
      datetime8: datetime8,
      datetime9: datetime9,
      conn: conn
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
             "datetime" => "2017-05-13T00:00:00.00Z",
             "activeAddresses" => 5000
           } in active_addresses

    assert %{
             "datetime" => "2017-05-14T00:00:00.00Z",
             "activeAddresses" => 100
           } in active_addresses

    assert %{
             "datetime" => "2017-05-15T00:00:00.00Z",
             "activeAddresses" => 500
           } in active_addresses

    assert %{
             "datetime" => "2017-05-16T00:00:00.00Z",
             "activeAddresses" => 15000
           } in active_addresses

    assert %{
             "datetime" => "2017-05-17T00:00:00.00Z",
             "activeAddresses" => 65000
           } in active_addresses

    assert %{
             "datetime" => "2017-05-18T00:00:00.00Z",
             "activeAddresses" => 50
           } in active_addresses

    assert %{
             "datetime" => "2017-05-19T00:00:00.00Z",
             "activeAddresses" => 5
           } in active_addresses

    assert %{
             "datetime" => "2017-05-20T00:00:00.00Z",
             "activeAddresses" => 0
           } in active_addresses
  end

  test "fetch daily active addreses with aggregation - average for all the days in the interval",
       context do
    query = """
    {
      dailyActiveAddresses(
        slug: "#{context.slug}",
        from: "#{context.datetime1}",
        to: "#{context.datetime9}",
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

    # Tests that the datetime is adjusted so it's not before `from`
    assert %{
             "datetime" => "2017-05-13T00:00:00.00Z",
             "activeAddresses" => 2550
           } in active_addresses

    assert %{
             "datetime" => "2017-05-15T00:00:00.00Z",
             "activeAddresses" => 7750
           } in active_addresses

    assert %{
             "datetime" => "2017-05-17T00:00:00.00Z",
             "activeAddresses" => 32525
           } in active_addresses

    assert %{
             "datetime" => "2017-05-19T00:00:00.00Z",
             "activeAddresses" => 3
           } in active_addresses
  end

  test "zeroes returned for daily active addresses", context do
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

    assert %{"activeAddresses" => 0, "datetime" => "2017-05-03T00:00:00.00Z"} in active_addresses
    assert %{"activeAddresses" => 0, "datetime" => "2017-05-05T00:00:00.00Z"} in active_addresses
    assert %{"activeAddresses" => 0, "datetime" => "2017-05-07T00:00:00.00Z"} in active_addresses
    assert %{"activeAddresses" => 0, "datetime" => "2017-05-09T00:00:00.00Z"} in active_addresses
    assert %{"activeAddresses" => 0, "datetime" => "2017-05-11T00:00:00.00Z"} in active_addresses
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

    assert active_addresses == 10707
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

  test "days with no active addresses return 0", context do
    query = """
    {
      dailyActiveAddresses(
        slug: "#{context.slug}",
        from: "#{context.datetime8}",
        to: "#{context.datetime9}",
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

    assert [
             %{"activeAddresses" => 0, "datetime" => "2017-05-20T00:00:00.00Z"},
             %{"activeAddresses" => 0, "datetime" => "2017-05-21T00:00:00.00Z"},
             %{"activeAddresses" => 0, "datetime" => "2017-05-22T00:00:00.00Z"},
             %{"activeAddresses" => 100, "datetime" => "2017-05-23T00:00:00.00Z"}
           ] == active_addresses
  end
end
