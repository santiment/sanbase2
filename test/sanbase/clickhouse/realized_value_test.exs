defmodule Sanbase.Clickhouse.RealizedValueTest do
  use Sanbase.DataCase
  import Mock
  import Sanbase.Factory
  import Sanbase.DateTimeUtils, only: [from_iso8601_to_unix!: 1, from_iso8601!: 1]
  alias Sanbase.Clickhouse.RealizedValue
  require Sanbase.ClickhouseRepo

  setup do
    project = insert(:project, %{coinmarketcap_id: "santiment", ticker: "SAN"})

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
             [from_iso8601_to_unix!("2019-01-01T00:00:00Z"), 100_000, 10_000],
             [from_iso8601_to_unix!("2019-01-02T00:00:00Z"), 200_000, 20_000],
             [from_iso8601_to_unix!("2019-01-03T00:00:00Z"), 300_000, 30_000]
           ]
         }}
      end do
      result =
        RealizedValue.realized_value(context.slug, context.from, context.to, context.interval)

      assert result ==
               {:ok,
                [
                  %{
                    realized_value: 100_000,
                    non_exchange_realized_value: 10_000,
                    datetime: from_iso8601!("2019-01-01T00:00:00Z")
                  },
                  %{
                    realized_value: 200_000,
                    non_exchange_realized_value: 20_000,
                    datetime: from_iso8601!("2019-01-02T00:00:00Z")
                  },
                  %{
                    realized_value: 300_000,
                    non_exchange_realized_value: 30_000,
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
             [from_iso8601_to_unix!("2019-01-01T00:00:00Z"), 0, 0],
             [from_iso8601_to_unix!("2019-01-02T00:00:00Z"), 200_000, 20_000],
             [from_iso8601_to_unix!("2019-01-03T00:00:00Z"), 300_000, 30_000],
             [from_iso8601_to_unix!("2019-01-04T00:00:00Z"), 400_000, 40_000]
           ]
         }}
      end do
      result = RealizedValue.realized_value(context.slug, context.from, context.to, "2d")

      assert result ==
               {:ok,
                [
                  %{
                    realized_value: 0,
                    non_exchange_realized_value: 0,
                    datetime: from_iso8601!("2019-01-01T00:00:00Z")
                  },
                  %{
                    realized_value: 200_000,
                    non_exchange_realized_value: 20_000,
                    datetime: from_iso8601!("2019-01-02T00:00:00Z")
                  },
                  %{
                    realized_value: 300_000,
                    non_exchange_realized_value: 30_000,
                    datetime: from_iso8601!("2019-01-03T00:00:00Z")
                  },
                  %{
                    realized_value: 400_000,
                    non_exchange_realized_value: 40_000,
                    datetime: from_iso8601!("2019-01-04T00:00:00Z")
                  }
                ]}
    end
  end

  test "fills nulls with a previous datapoint value", context do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [from_iso8601_to_unix!("2019-01-01T00:00:00Z"), 100_000, 10_000],
             [from_iso8601_to_unix!("2019-01-02T00:00:00Z"), nil, nil],
             [from_iso8601_to_unix!("2019-01-03T00:00:00Z"), 300_000, 30_000]
           ]
         }}
      end do
      result =
        RealizedValue.realized_value(context.slug, context.from, context.to, context.interval)

      assert result ==
               {:ok,
                [
                  %{
                    realized_value: 100_000,
                    non_exchange_realized_value: 10_000,
                    datetime: from_iso8601!("2019-01-01T00:00:00Z")
                  },
                  %{
                    realized_value: 100_000,
                    non_exchange_realized_value: 10_000,
                    datetime: from_iso8601!("2019-01-02T00:00:00Z")
                  },
                  %{
                    realized_value: 300_000,
                    non_exchange_realized_value: 30_000,
                    datetime: from_iso8601!("2019-01-03T00:00:00Z")
                  }
                ]}
    end
  end

  test "won't fill null when it's the first element", context do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [from_iso8601_to_unix!("2019-01-01T00:00:00Z"), nil, nil],
             [from_iso8601_to_unix!("2019-01-02T00:00:00Z"), nil, nil],
             [from_iso8601_to_unix!("2019-01-03T00:00:00Z"), 300_000, 30_000]
           ]
         }}
      end do
      result =
        RealizedValue.realized_value(context.slug, context.from, context.to, context.interval)

      assert result ==
               {:ok,
                [
                  %{
                    realized_value: nil,
                    non_exchange_realized_value: nil,
                    datetime: from_iso8601!("2019-01-01T00:00:00Z")
                  },
                  %{
                    realized_value: nil,
                    non_exchange_realized_value: nil,
                    datetime: from_iso8601!("2019-01-02T00:00:00Z")
                  },
                  %{
                    realized_value: 300_000,
                    non_exchange_realized_value: 30_000,
                    datetime: from_iso8601!("2019-01-03T00:00:00Z")
                  }
                ]}
    end
  end

  test "returns empty array when query returns no rows", context do
    with_mock Sanbase.ClickhouseRepo, query: fn _, _ -> {:ok, %{rows: []}} end do
      result =
        RealizedValue.realized_value(context.slug, context.from, context.to, context.interval)

      assert result == {:ok, []}
    end
  end
end
