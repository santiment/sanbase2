defmodule Sanbase.Github.EtherbiApiTest do
  use SanbaseWeb.ConnCase
  use Phoenix.ConnTest

  import Sanbase.Utils, only: [parse_config_value: 1]
  import Mockery
  import Mock

  test "fetch burn rate", context do
    mock HTTPoison, :get,
        {:ok, %HTTPoison.Response{
          status_code: 200,
          body: "[[1514766000, 91716892495405965698400256],\
              [1514770144, 359319706108516227858038784],\
              [1514778068, 31034050000000001245184]]"
        }}

      ticker = "SAN"
      datetime1 = DateTime.from_naive!(~N[2018-01-01 12:00:00], "Etc/UTC")
      datetime2 = DateTime.from_naive!(~N[2017-01-01 21:45:00], "Etc/UTC")
      datetime1_unix = DateTime.to_unix(datetime1, :second)
      datetime2_unix = DateTime.to_unix(datetime2, :second)

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

  test "fetch transaction volume", context do
    mock HTTPoison, :get,
        {:ok, %HTTPoison.Response{status_code: 200, body: "[[1514765863, 5810803200000000000],
              [1514766007, 700000000000001803841],
              [1514770144, 1749612781540000000000]]"}}

      ticker = "SAN"
      datetime1 = DateTime.from_naive!(~N[2018-01-01 12:00:00], "Etc/UTC")
      datetime2 = DateTime.from_naive!(~N[2017-01-01 21:45:00], "Etc/UTC")
      datetime1_unix = DateTime.to_unix(datetime1, :second)
      datetime2_unix = DateTime.to_unix(datetime2, :second)

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

      assert %{"transactionVolume" => "5810803200000000000"} in transaction_volumes
      assert %{"transactionVolume" => "700000000000001803841"} in transaction_volumes
      assert %{"transactionVolume" => "1749612781540000000000"} in transaction_volumes
  end

  defp query_skeleton(query, query_name) do
    %{
      "operationName" => "#{query_name}",
      "query" => "query #{query_name} #{query}",
      "variables" => "{}"
    }
  end
end