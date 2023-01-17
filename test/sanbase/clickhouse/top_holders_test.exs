defmodule Sanbase.Clickhouse.TopHoldersTest do
  use Sanbase.DataCase

  import Sanbase.Factory

  alias Sanbase.Clickhouse.TopHolders

  setup do
    project = insert(:project, %{slug: "ethereum", ticker: "ETH"})

    [
      slug: project.slug,
      contract: "ETH",
      token_decimals: 18,
      interval: "1d",
      number_of_holders: 10,
      from: ~U[2019-01-01 00:00:00Z],
      to: ~U[2019-01-03 00:00:00Z]
    ]
  end

  test "returns data when clickhouse returns", context do
    rows = [
      [DateTime.to_unix(~U[2019-01-01 00:00:00Z]), 7.6, 5.2, 12.8],
      [DateTime.to_unix(~U[2019-01-02 00:00:00Z]), 7.1, 5.1, 12.2]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        TopHolders.percent_of_total_supply(
          context.slug,
          context.number_of_holders,
          context.from,
          context.to,
          context.interval
        )

      assert result ==
               {:ok,
                [
                  %{
                    in_exchanges: 7.6,
                    outside_exchanges: 5.2,
                    in_top_holders_total: 12.8,
                    datetime: ~U[2019-01-01T00:00:00Z]
                  },
                  %{
                    in_exchanges: 7.1,
                    outside_exchanges: 5.1,
                    in_top_holders_total: 12.2,
                    datetime: ~U[2019-01-02T00:00:00Z]
                  }
                ]}
    end)
  end

  test "returns empty array when query returns no rows", context do
    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: []}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        TopHolders.percent_of_total_supply(
          context.slug,
          context.number_of_holders,
          context.from,
          context.to,
          context.interval
        )

      assert result == {:ok, []}
    end)
  end
end
