defmodule Sanbase.Clickhouse.FeesTest do
  use Sanbase.DataCase

  import Sanbase.Factory

  test "#value_fees_list_to_result/1" do
    p1 = insert(:random_project)
    p2 = insert(:random_project)

    data = [
      [p1.slug, 600],
      [p1.contract_addresses |> hd() |> Map.get(:address), 100],
      [p2.slug, 500],
      [p2.slug, 500]
    ]

    result = Sanbase.Clickhouse.Fees.value_fees_list_to_result(data)

    # Test the rest of fields except project because it cannot be easily pattern matched
    result_no_project = Enum.map(result, &Map.delete(&1, :project))
    assert %{address: nil, fees: 700, slug: p1.slug, ticker: p1.ticker} in result_no_project
    assert %{address: nil, fees: 500, slug: p2.slug, ticker: p2.ticker} in result_no_project

    # Test the projects. They should be ordered in fees in decreasing order
    [%{project: result_p1}, %{project: result_p2}] = result
    %{slug: slug_p1, ticker: ticker_p1, name: name_p1} = p1
    %{slug: slug_p2, ticker: ticker_p2, name: name_p2} = p2
    assert %{slug: ^slug_p1, ticker: ^ticker_p1, name: ^name_p1} = result_p1
    assert %{slug: ^slug_p2, ticker: ^ticker_p2, name: ^name_p2} = result_p2
  end
end
