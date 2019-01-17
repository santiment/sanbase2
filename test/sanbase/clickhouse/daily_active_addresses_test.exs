defmodule SanbaseWeb.Clickhouse.DailyActiveAddressesTest do
  use Sanbase.DataCase
  require Sanbase.ClickhouseRepo
  import Mock
  import Sanbase.Factory
  import Sanbase.DateTimeUtils, only: [from_iso8601_to_unix!: 1, from_iso8601!: 1]
  alias Sanbase.Clickhouse.{Erc20DailyActiveAddresses, EthDailyActiveAddresses}

  setup do
    project =
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
      project: project,
      project2: project2
    ]
  end

  test "ERC20 average_active_addresses/3", context do
    contract1 = context.project.main_contract_address
    contract2 = context.project2.main_contract_address

    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [contract1, 5],
             [contract2, 8]
           ]
         }}
      end do
      assert Erc20DailyActiveAddresses.average_active_addresses(
               [contract1, contract2],
               Timex.shift(Timex.now(), days: -10),
               Timex.now()
             ) ==
               {:ok,
                [
                  {contract1, 5},
                  {contract2, 8}
                ]}
    end
  end

  test "ETH average_active_addresses/2" do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [[200_000]]
         }}
      end do
      assert EthDailyActiveAddresses.average_active_addresses(
               Timex.shift(Timex.now(), days: -10),
               Timex.now()
             ) == {:ok, 200_000}
    end
  end

  test "ERC20 average_active_addresses/4", context do
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
      assert Erc20DailyActiveAddresses.average_active_addresses(
               context.project.main_contract_address,
               Timex.shift(Timex.now(), days: -1),
               Timex.now(),
               "1d"
             ) ==
               {:ok,
                [
                  %{datetime: from_iso8601!("2019-01-08T00:00:00Z"), active_addresses: 200_000},
                  %{datetime: from_iso8601!("2019-01-09T00:00:00Z"), active_addresses: 100_000}
                ]}
    end
  end

  test "ETH average_active_addresses/3" do
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
      assert EthDailyActiveAddresses.average_active_addresses(
               Timex.shift(Timex.now(), days: -1),
               Timex.now(),
               "1d"
             ) ==
               {:ok,
                [
                  %{datetime: from_iso8601!("2019-01-08T00:00:00Z"), active_addresses: 200_000},
                  %{datetime: from_iso8601!("2019-01-09T00:00:00Z"), active_addresses: 100_000}
                ]}
    end
  end
end
