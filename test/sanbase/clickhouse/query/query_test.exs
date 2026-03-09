defmodule Sanbase.Clickhouse.QueryTest do
  use ExUnit.Case, async: true

  alias Sanbase.Clickhouse.Query

  test "interpolate replaces named placeholders from params map" do
    query = "SELECT {limit:UInt8}, {slug:String}, {labels:Array(String)}"

    assert Query.interpolate(query, %{
             "limit" => 3,
             "slug" => "bitcoin",
             "labels" => ["exchange", "whale"]
           }) == "SELECT 3, 'bitcoin', ['exchange','whale']"
  end

  test "interpolate still supports positional placeholders" do
    query = "SELECT {$0:Int32}, {$1:String}"

    assert Query.interpolate(query, [42, "ethereum"]) == "SELECT 42, 'ethereum'"
  end

  test "interpolate replaces typed placeholders with values" do
    sql = "SELECT {$0:Int32}, {$1:String}, {$2:Array(Int32)}"

    assert Query.interpolate(sql, [42, "bitcoin", [1, 2]]) == "SELECT 42, 'bitcoin', [1,2]"
  end
end
