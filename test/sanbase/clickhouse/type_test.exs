defmodule Sanbase.Clickhouse.TypeTest do
  use ExUnit.Case, async: true

  alias Sanbase.Clickhouse.Type

  test "infer chooses decimal family by precision, not only scale" do
    assert Type.infer(Decimal.new("0.0001")) |> IO.iodata_to_binary() == "Decimal32(4)"

    assert Type.infer(Decimal.new("12345678901234567890.12")) |> IO.iodata_to_binary() ==
             "Decimal128(2)"
  end

  test "infer tuples as ClickHouse tuples" do
    assert Type.infer({1, "bitcoin", true}) |> IO.iodata_to_binary() ==
             "Tuple(Int32, String, Bool)"
  end

  test "known_ch_type accepts Decimal precision overrides" do
    assert Type.known_ch_type?("Decimal(10,2)")
  end
end
