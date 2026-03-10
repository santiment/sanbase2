defmodule Sanbase.Price.SqlQueryTest do
  use ExUnit.Case, async: true

  alias Sanbase.Clickhouse.Query
  alias Sanbase.Price.SqlQuery

  test "price_for_timestamps_query uses Array(Int64) for timestamp arrays" do
    timestamp_array = [2_147_483_647, 2_147_483_648]

    query = SqlQuery.price_for_timestamps_query("bitcoin", timestamp_array, "cryptocompare")

    assert {:ok, %{sql: sql, args: args}} = Query.get_sql_args(query)
    assert sql =~ "arrayEnumerate({timestamp_array:Array(Int64)})"
    assert sql =~ "FROM (SELECT {timestamp_array:Array(Int64)} AS ts_array)"

    assert args == %{
             "slug" => "bitcoin",
             "timestamp_array" => timestamp_array,
             "source" => "cryptocompare"
           }
  end
end
