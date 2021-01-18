defmodule Sanbase.Clickhouse.FeesTest do
  use Sanbase.DataCase

  import Sanbase.Factory

  test "#value_fees_list_to_result/1" do
    p1 = insert(:random_project)
    p2 = insert(:random_project)

    data = [
      [p1.slug, 100],
      [p1.contract_addresses |> hd |> Map.get(:address), 100],
      [p2.slug, 500],
      [p2.slug, 500]
    ]

    result = Sanbase.Clickhouse.Fees.value_fees_list_to_result(data)

    assert %{address: nil, fees: 200, slug: p1.slug, ticker: p1.ticker} in result
    assert %{address: nil, fees: 500, slug: p2.slug, ticker: p2.ticker} in result
  end
end
