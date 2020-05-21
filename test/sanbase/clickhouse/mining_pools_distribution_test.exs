defmodule Sanbase.Clickhouse.MiningPoolsDistributionTest do
  use Sanbase.DataCase
  import Mock
  import Sanbase.DateTimeUtils, only: [from_iso8601_to_unix!: 1, from_iso8601!: 1]
  alias Sanbase.Clickhouse.MiningPoolsDistribution
  require Sanbase.ClickhouseRepo

  setup do
    [
      slug: "ethereum",
      from: ~U[2019-01-01T00:00:00Z],
      to: ~U[2019-01-03T00:00:00Z],
      interval: "1d"
    ]
  end

  test "when requested interval fits the values interval", context do
    rows = [
      [~U[2019-01-01T00:00:00Z] |> DateTime.to_unix(), 0.10, 0.40, 0.50],
      [~U[2019-01-02T00:00:00Z] |> DateTime.to_unix(), 0.20, 0.30, 0.50],
      [~U[2019-01-03T00:00:00Z] |> DateTime.to_unix(), 0.30, 0.20, 0.50]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        MiningPoolsDistribution.distribution(
          context.slug,
          context.from,
          context.to,
          context.interval
        )

      assert result ==
               {:ok,
                [
                  %{top3: 0.10, top10: 0.40, other: 0.50, datetime: ~U[2019-01-01T00:00:00Z]},
                  %{top3: 0.20, top10: 0.30, other: 0.50, datetime: ~U[2019-01-02T00:00:00Z]},
                  %{top3: 0.30, top10: 0.20, other: 0.50, datetime: ~U[2019-01-03T00:00:00Z]}
                ]}
    end)
  end

  test "when requested interval is not full", context do
    rows = [
      [~U[2019-01-01T00:00:00Z] |> DateTime.to_unix(), 0.10, 0.40, 0.50],
      [~U[2019-01-02T00:00:00Z] |> DateTime.to_unix(), 0.20, 0.30, 0.50],
      [~U[2019-01-03T00:00:00Z] |> DateTime.to_unix(), 0.30, 0.20, 0.50],
      [~U[2019-01-04T00:00:00Z] |> DateTime.to_unix(), 0.40, 0.10, 0.50]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result = MiningPoolsDistribution.distribution(context.slug, context.from, context.to, "2d")

      assert result ==
               {:ok,
                [
                  %{top3: 0.10, top10: 0.40, other: 0.50, datetime: ~U[2019-01-01T00:00:00Z]},
                  %{top3: 0.20, top10: 0.30, other: 0.50, datetime: ~U[2019-01-02T00:00:00Z]},
                  %{top3: 0.30, top10: 0.20, other: 0.50, datetime: ~U[2019-01-03T00:00:00Z]},
                  %{top3: 0.40, top10: 0.10, other: 0.50, datetime: ~U[2019-01-04T00:00:00Z]}
                ]}
    end)
  end

  test "returns empty array when query returns no rows", context do
    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: []}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        MiningPoolsDistribution.distribution(
          context.slug,
          context.from,
          context.to,
          context.interval
        )

      assert result == {:ok, []}
    end)
  end

  test "returns error when something except ethereum is requested", context do
    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: []}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        MiningPoolsDistribution.distribution(
          "unsupported",
          context.from,
          context.to,
          context.interval
        )

      assert result == {:error, "Currently only ethereum is supported!"}
    end)
  end
end
