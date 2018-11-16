defmodule SanbaseWeb.Graphql.Clickhouse.HistoricalBalancesTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Mock

  require Sanbase.ClickhouseRepo

  setup do
    [
      address: "0x321321321",
      from: Timex.parse!("2017-05-11T00:00:00Z", "{ISO:Extended}"),
      to: Timex.parse!("2017-05-20T00:00:00Z", "{ISO:Extended}"),
      interval: "1d"
    ]
  end

  test "historical balances", context do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [dt_str_to_unix_time("2017-05-13T00:00:00Z"), 2000],
             [dt_str_to_unix_time("2017-05-14T00:00:00Z"), 1800],
             [dt_str_to_unix_time("2017-05-15T00:00:00Z"), 1800],
             [dt_str_to_unix_time("2017-05-16T00:00:00Z"), 1500],
             [dt_str_to_unix_time("2017-05-17T00:00:00Z"), 1900],
             [dt_str_to_unix_time("2017-05-18T00:00:00Z"), 1000]
           ]
         }}
      end do
      query = hist_balances_query(context.address, context.from, context.to, context.interval)

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "historicalBalance"))

      hist_balance = json_response(result, 200)["data"]["historicalBalance"]

      assert hist_balance == [
               %{"balance" => 0, "datetime" => "2017-05-11T00:00:00Z"},
               %{"balance" => 0, "datetime" => "2017-05-12T00:00:00Z"},
               %{"balance" => 2000, "datetime" => "2017-05-13T00:00:00Z"},
               %{"balance" => 1800, "datetime" => "2017-05-14T00:00:00Z"},
               %{"balance" => 1800, "datetime" => "2017-05-15T00:00:00Z"},
               %{"balance" => 1500, "datetime" => "2017-05-16T00:00:00Z"},
               %{"balance" => 1900, "datetime" => "2017-05-17T00:00:00Z"},
               %{"balance" => 1000, "datetime" => "2017-05-18T00:00:00Z"},
               %{"balance" => 1000, "datetime" => "2017-05-19T00:00:00Z"},
               %{"balance" => 1000, "datetime" => "2017-05-20T00:00:00Z"}
             ]
    end
  end

  defp hist_balances_query(address, from, to, interval) do
    """
      {
        historicalBalance(
            address: "#{address}",
            from: "#{from}",
            to: "#{to}",
            interval: "#{interval}"
        ){
            datetime,
            balance
        }
      }
    """
  end

  defp dt_str_to_unix_time(dt_str) do
    Timex.parse!(dt_str, "{ISO:Extended}") |> DateTime.to_unix()
  end
end
