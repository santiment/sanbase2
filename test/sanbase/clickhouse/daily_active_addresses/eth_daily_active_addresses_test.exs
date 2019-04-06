defmodule Sanbase.Clickhouse.DailyActiveAddresses.EthDailyActiveAddressesTest do
  use Sanbase.DataCase
  require Sanbase.ClickhouseRepo
  import Mock
  import Sanbase.DateTimeUtils, only: [from_iso8601_to_unix!: 1, from_iso8601!: 1]
  alias Sanbase.Clickhouse.EthDailyActiveAddresses

  setup do
    [
      from: from_iso8601!("2019-01-01T00:00:00Z"),
      to: from_iso8601!("2019-01-03T00:00:00Z")
    ]
  end

  describe "average value for given period" do
    test "returns the average single value for active addresses", context do
      with_mock Sanbase.ClickhouseRepo,
        query: fn _, _ -> {:ok, %{rows: [[100_000]]}} end do
        result = EthDailyActiveAddresses.average_active_addresses(context.from, context.to)

        assert result == {:ok, 100_000}
      end
    end

    test "returns 0 when the database returns nil", context do
      with_mock Sanbase.ClickhouseRepo,
        query: fn _, _ -> {:ok, %{rows: [[nil]]}} end do
        result = EthDailyActiveAddresses.average_active_addresses(context.from, context.to)

        assert result == {:ok, 0}
      end
    end
  end

  test "returns a single current value for active addresses" do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ -> {:ok, %{rows: [[100_000]]}} end do
      result = EthDailyActiveAddresses.realtime_active_addresses()

      assert result == {:ok, 100_000}
    end
  end

  test "returns average active addresses for given period in chunks", context do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [from_iso8601_to_unix!("2019-01-08T00:00:00Z"), 200_000, 20_000, 10.0],
             [from_iso8601_to_unix!("2019-01-09T00:00:00Z"), 100_000, 10_000, 10.0]
           ]
         }}
      end do
      result =
        EthDailyActiveAddresses.average_active_addresses_with_deposits(
          context.from,
          context.to,
          "1d"
        )

      assert result ==
               {:ok,
                [
                  %{
                    datetime: from_iso8601!("2019-01-08T00:00:00Z"),
                    active_addresses: 200_000,
                    active_deposits: 20_000,
                    share_of_deposits: 10.0
                  },
                  %{
                    datetime: from_iso8601!("2019-01-09T00:00:00Z"),
                    active_addresses: 100_000,
                    active_deposits: 10_000,
                    share_of_deposits: 10.0
                  }
                ]}
    end
  end

  test "returns average active addresses with deposits share for given period in chunks",
       context do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [from_iso8601_to_unix!("2019-01-08T00:00:00Z"), 200_000, 20_000, 10.0],
             [from_iso8601_to_unix!("2019-01-09T00:00:00Z"), 100_000, 10_000, 10.0]
           ]
         }}
      end do
      result =
        EthDailyActiveAddresses.average_active_addresses_with_deposits(
          context.from,
          context.to,
          "1d"
        )

      assert result ==
               {:ok,
                [
                  %{
                    datetime: from_iso8601!("2019-01-08T00:00:00Z"),
                    active_addresses: 200_000,
                    active_deposits: 20_000,
                    share_of_deposits: 10.0
                  },
                  %{
                    datetime: from_iso8601!("2019-01-09T00:00:00Z"),
                    active_addresses: 100_000,
                    active_deposits: 10_000,
                    share_of_deposits: 10.0
                  }
                ]}
    end
  end
end
