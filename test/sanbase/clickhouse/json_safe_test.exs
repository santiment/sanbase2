defmodule Sanbase.Clickhouse.JsonSafeTest do
  use ExUnit.Case, async: true

  alias Sanbase.Clickhouse.JsonSafe

  test "converts values by their column type" do
    uuid = Ecto.UUID.generate()
    {:ok, uuid_bin} = Ecto.UUID.dump(uuid)
    nil_uuid = <<0::128>>
    md5 = :crypto.hash(:md5, "abc")
    map_uuid = Ecto.UUID.bingenerate()
    {:ok, map_uuid_str} = Ecto.UUID.load(map_uuid)

    types = [
      "UUID",
      "Nullable(UUID)",
      "FixedString(16)",
      "FixedString(8)",
      "IPv4",
      "IPv6",
      "Map(UUID, UInt8)",
      "Map(IPv4, UInt8)",
      "Tuple(String, IPv4)",
      "Array(Nullable(UUID))",
      "String"
    ]

    row = [
      uuid_bin,
      nil_uuid,
      md5,
      "abc" <> <<0, 0, 0, 0, 0>>,
      {127, 0, 0, 1},
      {0, 0, 0, 0, 0, 0, 0, 1},
      %{map_uuid => 1},
      %{{1, 2, 3, 4} => 2},
      {"s", {10, 0, 0, 1}},
      [uuid_bin, nil],
      <<255, 254>>
    ]

    assert [converted] = JsonSafe.rows([row], types)

    assert converted == [
             uuid,
             "00000000-0000-0000-0000-000000000000",
             "base64:" <> Base.encode64(md5),
             "abc",
             "127.0.0.1",
             "::1",
             %{map_uuid_str => 1},
             %{"1.2.3.4" => 2},
             ["s", "10.0.0.1"],
             [uuid, nil],
             "base64:" <> Base.encode64(<<255, 254>>)
           ]

    assert {:ok, _} = Jason.encode(converted)
  end

  test "converts by shape when the column types are unknown" do
    assert [[[1, "a"], %{"1" => "x"}, "base64:" <> _]] =
             JsonSafe.rows([[{1, "a"}, %{1 => "x"}, <<255>>]], nil)
  end
end
