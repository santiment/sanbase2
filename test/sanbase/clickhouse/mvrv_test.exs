defmodule Sanbase.Clickhouse.MVRVTest do
  use Sanbase.DataCase
  import Mock
  import Sanbase.Factory
  import Sanbase.DateTimeUtils, only: [from_iso8601_to_unix!: 1, from_iso8601!: 1]
  alias Sanbase.Clickhouse.MVRV
  require Sanbase.ClickhouseRepo

  setup do
    project = insert(:project, %{coinmarketcap_id: "ethereum", ticker: "ETH"})

    [
      slug: project.coinmarketcap_id,
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
             [from_iso8601_to_unix!("2019-01-01T00:00:00Z"), 0.0],
             [from_iso8601_to_unix!("2019-01-02T00:00:00Z"), 0.22],
             [from_iso8601_to_unix!("2019-01-03T00:00:00Z"), 0.33]
           ]
         }}
      end do
      result = MVRV.mvrv_ratio(context.slug, context.from, context.to, context.interval)

      assert result ==
               {:ok,
                [
                  %{ratio: 0.0, datetime: from_iso8601!("2019-01-01T00:00:00Z")},
                  %{ratio: 0.22, datetime: from_iso8601!("2019-01-02T00:00:00Z")},
                  %{ratio: 0.33, datetime: from_iso8601!("2019-01-03T00:00:00Z")}
                ]}
    end
  end

  test "when requested interval is not full", context do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [from_iso8601_to_unix!("2019-01-01T00:00:00Z"), 0.0],
             [from_iso8601_to_unix!("2019-01-02T00:00:00Z"), 0.22],
             [from_iso8601_to_unix!("2019-01-03T00:00:00Z"), 0.33],
             [from_iso8601_to_unix!("2019-01-04T00:00:00Z"), 0.44]
           ]
         }}
      end do
      result = MVRV.mvrv_ratio(context.slug, context.from, context.to, "2d")

      assert result ==
               {:ok,
                [
                  %{ratio: 0.0, datetime: from_iso8601!("2019-01-01T00:00:00Z")},
                  %{ratio: 0.22, datetime: from_iso8601!("2019-01-02T00:00:00Z")},
                  %{ratio: 0.33, datetime: from_iso8601!("2019-01-03T00:00:00Z")},
                  %{ratio: 0.44, datetime: from_iso8601!("2019-01-04T00:00:00Z")}
                ]}
    end
  end

  test "fills nulls with a previous datapoint value", context do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [from_iso8601_to_unix!("2019-01-01T00:00:00Z"), 0.1],
             [from_iso8601_to_unix!("2019-01-02T00:00:00Z"), nil],
             [from_iso8601_to_unix!("2019-01-03T00:00:00Z"), 0.2]
           ]
         }}
      end do
      result = MVRV.mvrv_ratio(context.slug, context.from, context.to, context.interval)

      assert result ==
               {:ok,
                [
                  %{ratio: 0.1, datetime: from_iso8601!("2019-01-01T00:00:00Z")},
                  %{ratio: 0.1, datetime: from_iso8601!("2019-01-02T00:00:00Z")},
                  %{ratio: 0.2, datetime: from_iso8601!("2019-01-03T00:00:00Z")}
                ]}
    end
  end

  test "won't fill null when it's the first element", context do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [from_iso8601_to_unix!("2019-01-01T00:00:00Z"), nil],
             [from_iso8601_to_unix!("2019-01-02T00:00:00Z"), nil],
             [from_iso8601_to_unix!("2019-01-03T00:00:00Z"), 0.2]
           ]
         }}
      end do
      result = MVRV.mvrv_ratio(context.slug, context.from, context.to, context.interval)

      assert result ==
               {:ok,
                [
                  %{ratio: nil, datetime: from_iso8601!("2019-01-01T00:00:00Z")},
                  %{ratio: nil, datetime: from_iso8601!("2019-01-02T00:00:00Z")},
                  %{ratio: 0.2, datetime: from_iso8601!("2019-01-03T00:00:00Z")}
                ]}
    end
  end

  test "returns empty array when query returns no rows", context do
    with_mock Sanbase.ClickhouseRepo, query: fn _, _ -> {:ok, %{rows: []}} end do
      result = MVRV.mvrv_ratio(context.slug, context.from, context.to, context.interval)

      assert result == {:ok, []}
    end
  end
end
