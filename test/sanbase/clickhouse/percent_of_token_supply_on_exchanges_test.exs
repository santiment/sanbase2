defmodule Sanbase.Clickhouse.PercentOfTokenSupplyOnExchangesTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.DateTimeUtils, only: [from_iso8601_to_unix!: 1, from_iso8601!: 1]
  import Sanbase.Factory

  alias Sanbase.Clickhouse.PercentOfTokenSupplyOnExchanges
  require Sanbase.ClickhouseRepo

  setup do
    project = insert(:project)

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
             [from_iso8601_to_unix!("2019-01-01T00:00:00Z"), 0.111],
             [from_iso8601_to_unix!("2019-01-02T00:00:00Z"), 0.022],
             [from_iso8601_to_unix!("2019-01-03T00:00:00Z"), 0.03]
           ]
         }}
      end do
      result =
        PercentOfTokenSupplyOnExchanges.percent_on_exchanges(
          context.slug,
          context.from,
          context.to,
          context.interval
        )

      assert result ==
               {:ok,
                [
                  %{
                    percent_on_exchanges: 11.1,
                    datetime: from_iso8601!("2019-01-01T00:00:00Z")
                  },
                  %{
                    percent_on_exchanges: 2.1999999999999997,
                    datetime: from_iso8601!("2019-01-02T00:00:00Z")
                  },
                  %{
                    percent_on_exchanges: 3.0,
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
             [from_iso8601_to_unix!("2019-01-01T00:00:00Z"), 0.111],
             [from_iso8601_to_unix!("2019-01-02T00:00:00Z"), 0.022],
             [from_iso8601_to_unix!("2019-01-03T00:00:00Z"), 0.33],
             [from_iso8601_to_unix!("2019-01-04T00:00:00Z"), 0.04]
           ]
         }}
      end do
      result =
        PercentOfTokenSupplyOnExchanges.percent_on_exchanges(
          context.slug,
          context.from,
          context.to,
          "2d"
        )

      assert result ==
               {:ok,
                [
                  %{
                    percent_on_exchanges: 11.1,
                    datetime: from_iso8601!("2019-01-01T00:00:00Z")
                  },
                  %{
                    percent_on_exchanges: 2.1999999999999997,
                    datetime: from_iso8601!("2019-01-02T00:00:00Z")
                  },
                  %{
                    percent_on_exchanges: 33.0,
                    datetime: from_iso8601!("2019-01-03T00:00:00Z")
                  },
                  %{
                    percent_on_exchanges: 4.0,
                    datetime: from_iso8601!("2019-01-04T00:00:00Z")
                  }
                ]}
    end
  end

  test "returns empty array when query returns no rows", context do
    with_mock Sanbase.ClickhouseRepo, query: fn _, _ -> {:ok, %{rows: []}} end do
      result =
        PercentOfTokenSupplyOnExchanges.percent_on_exchanges(
          context.slug,
          context.from,
          context.to,
          context.interval
        )

      assert result == {:ok, []}
    end
  end
end
