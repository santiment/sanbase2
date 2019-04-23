defmodule Sanbase.Clickhouse.MiningPoolsDistributionTest do
  use Sanbase.DataCase
  import Mock
  import Sanbase.DateTimeUtils, only: [from_iso8601_to_unix!: 1, from_iso8601!: 1]
  alias Sanbase.Clickhouse.MiningPoolsDistribution
  require Sanbase.ClickhouseRepo

  setup do
    [
      from: from_iso8601!("2019-01-01T00:00:00Z"),
      to: from_iso8601!("2019-01-03T00:00:00Z"),
      interval: "1d"
    ]
  end

  test "when requested interval fits the values interval", context do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [from_iso8601_to_unix!("2019-01-01T00:00:00Z"), 0.10, 0.40, 0.50],
             [from_iso8601_to_unix!("2019-01-02T00:00:00Z"), 0.20, 0.30, 0.50],
             [from_iso8601_to_unix!("2019-01-03T00:00:00Z"), 0.30, 0.20, 0.50]
           ]
         }}
      end do
      result = MiningPoolsDistribution.distribution(context.from, context.to, context.interval)

      assert result ==
               {:ok,
                [
                  %{
                    top3: 0.10,
                    top10: 0.40,
                    other: 0.50,
                    datetime: from_iso8601!("2019-01-01T00:00:00Z")
                  },
                  %{
                    top3: 0.20,
                    top10: 0.30,
                    other: 0.50,
                    datetime: from_iso8601!("2019-01-02T00:00:00Z")
                  },
                  %{
                    top3: 0.30,
                    top10: 0.20,
                    other: 0.50,
                    datetime: from_iso8601!("2019-01-03T00:00:00Z")
                  }
                ]}
    end
  end

  test "when requested interval is not full", context do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [from_iso8601_to_unix!("2019-01-01T00:00:00Z"), 0.10, 0.40, 0.50],
             [from_iso8601_to_unix!("2019-01-02T00:00:00Z"), 0.20, 0.30, 0.50],
             [from_iso8601_to_unix!("2019-01-03T00:00:00Z"), 0.30, 0.20, 0.50],
             [from_iso8601_to_unix!("2019-01-04T00:00:00Z"), 0.40, 0.10, 0.50]
           ]
         }}
      end do
      result = MiningPoolsDistribution.distribution(context.from, context.to, "2d")

      assert result ==
               {:ok,
                [
                  %{
                    top3: 0.10,
                    top10: 0.40,
                    other: 0.50,
                    datetime: from_iso8601!("2019-01-01T00:00:00Z")
                  },
                  %{
                    top3: 0.20,
                    top10: 0.30,
                    other: 0.50,
                    datetime: from_iso8601!("2019-01-02T00:00:00Z")
                  },
                  %{
                    top3: 0.30,
                    top10: 0.20,
                    other: 0.50,
                    datetime: from_iso8601!("2019-01-03T00:00:00Z")
                  },
                  %{
                    top3: 0.40,
                    top10: 0.10,
                    other: 0.50,
                    datetime: from_iso8601!("2019-01-04T00:00:00Z")
                  }
                ]}
    end
  end

  test "returns empty array when query returns no rows", context do
    with_mock Sanbase.ClickhouseRepo, query: fn _, _ -> {:ok, %{rows: []}} end do
      result = MiningPoolsDistribution.distribution(context.from, context.to, context.interval)

      assert result == {:ok, []}
    end
  end
end
