defmodule SanbaseWeb.Clickhouse.DailyActiveDepositsTest do
  use Sanbase.DataCase
  import Mock
  import Sanbase.Factory
  import Sanbase.DateTimeUtils, only: [from_iso8601_to_unix!: 1, from_iso8601!: 1]
  alias Sanbase.Clickhouse.DailyActiveDeposits
  require Sanbase.ClickhouseRepo

  setup do
    project = insert(:project, %{main_contract_address: "0x123"})

    [
      contract: project.main_contract_address,
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
             [from_iso8601_to_unix!("2019-01-01T00:00:00Z"), 0],
             [from_iso8601_to_unix!("2019-01-02T00:00:00Z"), "100"],
             [from_iso8601_to_unix!("2019-01-03T00:00:00Z"), 200]
           ]
         }}
      end do
      result =
        DailyActiveDeposits.active_deposits(
          context.contract,
          context.from,
          context.to,
          context.interval
        )

      assert result ==
               {:ok,
                [
                  %{active_deposits: 0.0, datetime: from_iso8601!("2019-01-01T00:00:00Z")},
                  %{active_deposits: 100, datetime: from_iso8601!("2019-01-02T00:00:00Z")},
                  %{active_deposits: 200, datetime: from_iso8601!("2019-01-03T00:00:00Z")}
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
             [from_iso8601_to_unix!("2019-01-02T00:00:00Z"), 100],
             [from_iso8601_to_unix!("2019-01-03T00:00:00Z"), 200],
             [from_iso8601_to_unix!("2019-01-04T00:00:00Z"), 300]
           ]
         }}
      end do
      result =
        DailyActiveDeposits.active_deposits(context.contract, context.from, context.to, "2d")

      assert result ==
               {:ok,
                [
                  %{active_deposits: 0.0, datetime: from_iso8601!("2019-01-01T00:00:00Z")},
                  %{active_deposits: 100, datetime: from_iso8601!("2019-01-02T00:00:00Z")},
                  %{active_deposits: 200, datetime: from_iso8601!("2019-01-03T00:00:00Z")},
                  %{active_deposits: 300, datetime: from_iso8601!("2019-01-04T00:00:00Z")}
                ]}
    end
  end

  test "returns empty array when query returns no rows", context do
    with_mock Sanbase.ClickhouseRepo, query: fn _, _ -> {:ok, %{rows: []}} end do
      result =
        DailyActiveDeposits.active_deposits(
          context.contract,
          context.from,
          context.to,
          context.interval
        )

      assert result == {:ok, []}
    end
  end
end
