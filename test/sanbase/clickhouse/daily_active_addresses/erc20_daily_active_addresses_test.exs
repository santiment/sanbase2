defmodule Sanbase.Clickhouse.DailyActiveAddresses.Erc20DailyActiveAddressesTest do
  use Sanbase.DataCase
  require Sanbase.ClickhouseRepo
  import Mock
  import Sanbase.Factory
  import Sanbase.DateTimeUtils, only: [from_iso8601_to_unix!: 1, from_iso8601!: 1]
  alias Sanbase.Clickhouse.Erc20DailyActiveAddresses

  setup do
    project1 =
      insert(:project, %{
        ticker: "PRJ1",
        coinmarketcap_id: "project1",
        main_contract_address: "0x123"
      })

    project2 =
      insert(:project, %{
        ticker: "PRJ2",
        coinmarketcap_id: "project2",
        main_contract_address: "0x456"
      })

    [
      project1: project1,
      contract1: project1.main_contract_address,
      project2: project2,
      contract2: project2.main_contract_address,
      from: from_iso8601!("2019-01-01T00:00:00Z"),
      to: from_iso8601!("2019-01-03T00:00:00Z")
    ]
  end

  test "returns a single current value for active addresses per contract", context do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok, %{rows: [["0x123", 100_000], ["0x456", 200_000]]}}
      end do
      result =
        Erc20DailyActiveAddresses.realtime_active_addresses([context.contract1, context.contract2])

      assert result == {:ok, [{"0x123", 100_000}, {"0x456", 200_000}]}
    end
  end

  test "returns average active addresses for given period per contract", context do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok, %{rows: [[context.contract1, 5], [context.contract2, 8]]}}
      end do
      result =
        Erc20DailyActiveAddresses.average_active_addresses(
          [context.contract1, context.contract2],
          context.from,
          context.to
        )

      assert result ==
               {:ok, [{context.contract1, 5}, {context.contract2, 8}]}
    end
  end

  test "returns active addresses for given period and contract in chunks", context do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [from_iso8601_to_unix!("2019-01-08T00:00:00Z"), 200_000],
             [from_iso8601_to_unix!("2019-01-09T00:00:00Z"), 100_000]
           ]
         }}
      end do
      result =
        Erc20DailyActiveAddresses.average_active_addresses(
          context.contract1,
          context.from,
          context.to,
          "1d"
        )

      assert result ==
               {:ok,
                [
                  %{
                    datetime: from_iso8601!("2019-01-08T00:00:00Z"),
                    active_addresses: 200_000
                  },
                  %{
                    datetime: from_iso8601!("2019-01-09T00:00:00Z"),
                    active_addresses: 100_000
                  }
                ]}
    end
  end
end
