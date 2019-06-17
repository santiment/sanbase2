defmodule Sanbase.Clickhouse.HistoricalBalance.MinersBalanceTest do
  use Sanbase.DataCase
  import Mock
  import Sanbase.DateTimeUtils, only: [from_iso8601_to_unix!: 1, from_iso8601!: 1]
  alias Sanbase.Clickhouse.HistoricalBalance.MinersBalance
  require Sanbase.ClickhouseRepo

  setup do
    [
      slug: "ethereum",
      from: from_iso8601!("2019-01-01T00:00:00Z"),
      to: from_iso8601!("2019-01-04T00:00:00Z")
    ]
  end

  test "works for intervals in days", context do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [from_iso8601_to_unix!("2019-01-01T00:00:00Z"), 100_000],
             [from_iso8601_to_unix!("2019-01-02T00:00:00Z"), 200_000],
             [from_iso8601_to_unix!("2019-01-03T00:00:00Z"), 300_000],
             [from_iso8601_to_unix!("2019-01-04T00:00:00Z"), 400_000]
           ]
         }}
      end do
      result = MinersBalance.historical_balance(context.slug, context.from, context.to, "1d")

      assert result ==
               {:ok,
                [
                  %{
                    balance: 100_000,
                    datetime: from_iso8601!("2019-01-01T00:00:00Z")
                  },
                  %{
                    balance: 200_000,
                    datetime: from_iso8601!("2019-01-02T00:00:00Z")
                  },
                  %{
                    balance: 300_000,
                    datetime: from_iso8601!("2019-01-03T00:00:00Z")
                  },
                  %{
                    balance: 400_000,
                    datetime: from_iso8601!("2019-01-04T00:00:00Z")
                  }
                ]}
    end
  end

  test "works for intervals in hours", context do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [from_iso8601_to_unix!("2019-01-01T00:00:00Z"), 100_000],
             [from_iso8601_to_unix!("2019-01-02T00:00:00Z"), 200_000],
             [from_iso8601_to_unix!("2019-01-03T00:00:00Z"), 300_000],
             [from_iso8601_to_unix!("2019-01-04T00:00:00Z"), 400_000]
           ]
         }}
      end do
      result = MinersBalance.historical_balance(context.slug, context.from, context.to, "24h")

      assert result ==
               {:ok,
                [
                  %{
                    balance: 100_000,
                    datetime: from_iso8601!("2019-01-01T00:00:00Z")
                  },
                  %{
                    balance: 200_000,
                    datetime: from_iso8601!("2019-01-02T00:00:00Z")
                  },
                  %{
                    balance: 300_000,
                    datetime: from_iso8601!("2019-01-03T00:00:00Z")
                  },
                  %{
                    balance: 400_000,
                    datetime: from_iso8601!("2019-01-04T00:00:00Z")
                  }
                ]}
    end
  end

  test "returns empty array when query returns no rows", context do
    with_mock Sanbase.ClickhouseRepo, query: fn _, _ -> {:ok, %{rows: []}} end do
      result = MinersBalance.historical_balance(context.slug, context.from, context.to, "1d")

      assert result == {:ok, []}
    end
  end

  test "returns error when requested interval is less than a day", context do
    result = MinersBalance.historical_balance(context.slug, context.from, context.to, "23h")

    assert result == {:error, "The interval must consist of whole days!"}
  end

  test "returns error when something except ethereum is requested", context do
    with_mock Sanbase.ClickhouseRepo, query: fn _, _ -> {:ok, %{rows: []}} end do
      result =
        MinersBalance.historical_balance(
          "unsupported",
          context.from,
          context.to,
          "1d"
        )

      assert result == {:error, "Currently only ethereum is supported!"}
    end
  end
end
