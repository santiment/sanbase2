defmodule Sanbase.Github.EtherbiApiTest do
  use SanbaseWeb.ConnCase

  import Mockery
  import SanbaseWeb.Graphql.TestHelpers

  test "fetch burn rate", context do
    burn_rate = [
      [1514766000, 91716892495405965698400256],
      [1514770144, 359319706108516227858038784],
      [1514778068, 31034050000000001245184]
    ]

    mock HTTPoison, :get,
        {:ok, %HTTPoison.Response{
          status_code: 200,
          body: Poison.encode!(burn_rate)
        }}

      ticker = "SAN"
      datetime1 = DateTime.from_naive!(~N[2018-01-01 12:00:00], "Etc/UTC")
      datetime2 = DateTime.from_naive!(~N[2017-01-01 21:45:00], "Etc/UTC")

      query = """
      {
        burnRate(
          ticker: "#{ticker}",
          from: "#{datetime1}",
          to: "#{datetime2}")
          {
            burnRate
          }
        }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "burnRate"))

      burn_rates = json_response(result, 200)["data"]["burnRate"]

      assert %{"burnRate" => "91716892495405965698400256"} in burn_rates
      assert %{"burnRate" => "359319706108516227858038784"} in burn_rates
      assert %{"burnRate" => "31034050000000001245184"} in burn_rates
  end

  test "fetch big response for the burn rate", context do
    burn_rate = Stream.cycle([
      [1514766000, 91716892495405965698400256],
      [1514770144, 359319706108516227858038784],
      [1514778068, 31034050000000001245184]
    ])
    |> Enum.take(20000)

    mock HTTPoison, :get,
        {:ok, %HTTPoison.Response{
          status_code: 200,
          body: Poison.encode!(burn_rate)
        }}

      ticker = "SAN"
      datetime1 = DateTime.from_naive!(~N[2018-01-01 12:00:00], "Etc/UTC")
      datetime2 = DateTime.from_naive!(~N[2017-01-01 21:45:00], "Etc/UTC")

      query = """
      {
        burnRate(
          ticker: "#{ticker}",
          from: "#{datetime1}",
          to: "#{datetime2}")
          {
            burnRate
          }
        }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "burnRate"))

      burn_rates = json_response(result, 200)["data"]["burnRate"]

      assert length(burn_rates) == 500
  end

  test "fetch transaction volume", context do
    transaction_volume = Stream.cycle([
      [1514765863, 5810803200000000000],
      [1514766007, 700000000000001803841],
      [1514770144, 1749612781540000000000]
    ])
    |> Enum.take(21000)

    mock HTTPoison, :get,
        {:ok, %HTTPoison.Response{status_code: 200, body: Poison.encode!(transaction_volume)}}

      ticker = "SAN"
      datetime1 = DateTime.from_naive!(~N[2018-01-01 12:00:00], "Etc/UTC")
      datetime2 = DateTime.from_naive!(~N[2017-01-01 21:45:00], "Etc/UTC")

      query = """
      {
        transactionVolume(
          ticker: "#{ticker}",
          from: "#{datetime1}",
          to: "#{datetime2}")
          {
            transactionVolume
          }
        }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "transactionVolume"))

      transaction_volumes = json_response(result, 200)["data"]["transactionVolume"]

      assert length(transaction_volumes) == 500
  end
end
