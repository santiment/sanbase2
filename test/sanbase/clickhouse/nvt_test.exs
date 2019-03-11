defmodule SanbaseWeb.Graphql.Clickhouse.NVTTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.DateTimeUtils, only: [from_iso8601_to_unix!: 1, from_iso8601!: 1]
  import Sanbase.Factory

  alias Sanbase.Clickhouse.NVT
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
             [from_iso8601_to_unix!("2019-01-01T00:00:00Z"), 101, 0.1, 0.11],
             [from_iso8601_to_unix!("2019-01-02T00:00:00Z"), 102, 0.2, 0.22],
             [from_iso8601_to_unix!("2019-01-03T00:00:00Z"), 103, 0.3, 0.33]
           ]
         }}
      end do
      result = NVT.nvt_ratio(context.slug, context.from, context.to, context.interval)

      assert result ==
               {:ok,
                [
                  %{
                    nvt_ratio_circulation: 0.1,
                    nvt_ratio_tx_volume: 0.11,
                    datetime: from_iso8601!("2019-01-01T00:00:00Z")
                  },
                  %{
                    nvt_ratio_circulation: 0.2,
                    nvt_ratio_tx_volume: 0.22,
                    datetime: from_iso8601!("2019-01-02T00:00:00Z")
                  },
                  %{
                    nvt_ratio_circulation: 0.3,
                    nvt_ratio_tx_volume: 0.33,
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
             [from_iso8601_to_unix!("2019-01-01T00:00:00Z"), 101, 0.1, 0.01],
             [from_iso8601_to_unix!("2019-01-02T00:00:00Z"), 102, 0.2, 0.02],
             [from_iso8601_to_unix!("2019-01-03T00:00:00Z"), 103, 0.3, 0.03],
             [from_iso8601_to_unix!("2019-01-04T00:00:00Z"), 104, 0.4, 0.04]
           ]
         }}
      end do
      result = NVT.nvt_ratio(context.slug, context.from, context.to, "2d")

      assert result ==
               {:ok,
                [
                  %{
                    nvt_ratio_circulation: 0.1,
                    nvt_ratio_tx_volume: 0.01,
                    datetime: from_iso8601!("2019-01-01T00:00:00Z")
                  },
                  %{
                    nvt_ratio_circulation: 0.2,
                    nvt_ratio_tx_volume: 0.02,
                    datetime: from_iso8601!("2019-01-02T00:00:00Z")
                  },
                  %{
                    nvt_ratio_circulation: 0.3,
                    nvt_ratio_tx_volume: 0.03,
                    datetime: from_iso8601!("2019-01-03T00:00:00Z")
                  },
                  %{
                    nvt_ratio_circulation: 0.4,
                    nvt_ratio_tx_volume: 0.04,
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
             [from_iso8601_to_unix!("2019-01-01T00:00:00Z"), 101, 0.1, 0.11],
             [from_iso8601_to_unix!("2019-01-02T00:00:00Z"), nil, nil, nil],
             [from_iso8601_to_unix!("2019-01-03T00:00:00Z"), 102, 0.2, 0.22]
           ]
         }}
      end do
      result = NVT.nvt_ratio(context.slug, context.from, context.to, context.interval)

      assert result ==
               {:ok,
                [
                  %{
                    nvt_ratio_circulation: 0.1,
                    nvt_ratio_tx_volume: 0.11,
                    datetime: from_iso8601!("2019-01-01T00:00:00Z")
                  },
                  %{
                    nvt_ratio_circulation: 0.1,
                    nvt_ratio_tx_volume: 0.11,
                    datetime: from_iso8601!("2019-01-02T00:00:00Z")
                  },
                  %{
                    nvt_ratio_circulation: 0.2,
                    nvt_ratio_tx_volume: 0.22,
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
             [from_iso8601_to_unix!("2019-01-01T00:00:00Z"), nil, nil, nil],
             [from_iso8601_to_unix!("2019-01-02T00:00:00Z"), nil, nil, nil],
             [from_iso8601_to_unix!("2019-01-03T00:00:00Z"), 102, 0.2, 0.22]
           ]
         }}
      end do
      result = NVT.nvt_ratio(context.slug, context.from, context.to, context.interval)

      assert result ==
               {:ok,
                [
                  %{
                    nvt_ratio_circulation: nil,
                    nvt_ratio_tx_volume: nil,
                    datetime: from_iso8601!("2019-01-01T00:00:00Z")
                  },
                  %{
                    nvt_ratio_circulation: nil,
                    nvt_ratio_tx_volume: nil,
                    datetime: from_iso8601!("2019-01-02T00:00:00Z")
                  },
                  %{
                    nvt_ratio_circulation: 0.2,
                    nvt_ratio_tx_volume: 0.22,
                    datetime: from_iso8601!("2019-01-03T00:00:00Z")
                  }
                ]}
    end
  end

  test "returns empty array when query returns no rows", context do
    with_mock Sanbase.ClickhouseRepo, query: fn _, _ -> {:ok, %{rows: []}} end do
      result = NVT.nvt_ratio(context.slug, context.from, context.to, context.interval)

      assert result == {:ok, []}
    end
  end
end
