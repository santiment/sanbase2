defmodule Sanbase.Clickhouse.DailyActiveAddresses.EthDailyActiveAddressesTest do
  use Sanbase.DataCase
  require Sanbase.ClickhouseRepo
  import Mock
  import Sanbase.DateTimeUtils, only: [from_iso8601_to_unix!: 1, from_iso8601!: 1]
  alias Sanbase.Clickhouse.EthDailyActiveAddresses, as: Eth

  setup do
    [
      from: from_iso8601!("2019-01-01T00:00:00Z"),
      to: from_iso8601!("2019-01-02T00:00:00Z")
    ]
  end

  describe "average value for given period" do
    test "returns the average single value for active addresses", context do
      with_mock Sanbase.ClickhouseRepo,
                [:passthrough],
                query: fn _, _ -> {:ok, %{rows: [[100_000]]}} end do
        result = Eth.average_active_addresses(context.from, context.to)

        assert result == {:ok, 100_000}
      end
    end

    test "returns 0 when the database returns nil", context do
      with_mock Sanbase.ClickhouseRepo,
                [:passthrough],
                query: fn _, _ -> {:ok, %{rows: [[nil]]}} end do
        result = Eth.average_active_addresses(context.from, context.to)

        assert result == {:ok, 0}
      end
    end
  end

  test "returns a single current value for active addresses" do
    with_mock Sanbase.ClickhouseRepo,
              [:passthrough],
              query: fn _, _ -> {:ok, %{rows: [[100_000]]}} end do
      result = Eth.realtime_active_addresses()

      assert result == {:ok, 100_000}
    end
  end

  test "returns average active addresses for given period in chunks", context do
    with_mock Sanbase.ClickhouseRepo,
              [:passthrough],
              query: fn _, _ ->
                {:ok,
                 %{
                   rows: [
                     [from_iso8601_to_unix!("2019-01-01T00:00:00Z"), 100_000],
                     [from_iso8601_to_unix!("2019-01-02T00:00:00Z"), 200_000]
                   ]
                 }}
              end do
      result = Eth.average_active_addresses(context.from, context.to, "1d")

      assert result ==
               {:ok,
                [
                  %{
                    datetime: from_iso8601!("2019-01-01T00:00:00Z"),
                    active_addresses: 100_000
                  },
                  %{
                    datetime: from_iso8601!("2019-01-02T00:00:00Z"),
                    active_addresses: 200_000
                  }
                ]}
    end
  end
end
