defmodule Sanbase.Blockchain.DailyActiveAddressesTest do
  use Sanbase.DataCase, async: false
  @moduletag datacase_repo: Sanbase.TimescaleRepo
  @moduletag timescaledb: true

  import Sanbase.TimescaleFactory

  alias Sanbase.Blockchain.DailyActiveAddresses
  alias Sanbase.DateTimeUtils

  setup do
    contract1 = "0x123123"

    datetime1 = DateTime.from_naive!(~N[2017-05-13 00:00:00], "Etc/UTC")
    datetime2 = DateTime.from_naive!(~N[2017-05-14 00:00:00], "Etc/UTC")
    datetime3 = DateTime.from_naive!(~N[2017-05-16 00:00:00], "Etc/UTC")
    datetime4 = DateTime.from_naive!(~N[2017-05-18 00:00:00], "Etc/UTC")

    insert(:daily_active_addresses, %{
      contract_address: contract1,
      timestamp: datetime1,
      active_addresses: 500
    })

    insert(:daily_active_addresses, %{
      contract_address: contract1,
      timestamp: datetime2,
      active_addresses: 1500
    })

    insert(:daily_active_addresses, %{
      contract_address: contract1,
      timestamp: datetime3,
      active_addresses: 2500
    })

    insert(:daily_active_addresses, %{
      contract_address: contract1,
      timestamp: datetime4,
      active_addresses: 100
    })

    %{
      contract: contract1,
      datetime_from: datetime1,
      datetime_to: datetime4
    }
  end

  test "daily active addresses fill gaps", context do
    assert {:ok, result} =
             DailyActiveAddresses.active_addresses(
               context.contract,
               context.datetime_from,
               context.datetime_to,
               "1d"
             )

    assert result == [
             %{
               active_addresses: 500,
               datetime: DateTimeUtils.from_iso8601!("2017-05-13 00:00:00.000000Z")
             },
             %{
               active_addresses: 1500,
               datetime: DateTimeUtils.from_iso8601!("2017-05-14 00:00:00.000000Z")
             },
             %{
               active_addresses: 0,
               datetime: DateTimeUtils.from_iso8601!("2017-05-15 00:00:00.000000Z")
             },
             %{
               active_addresses: 2500,
               datetime: DateTimeUtils.from_iso8601!("2017-05-16 00:00:00.000000Z")
             },
             %{
               active_addresses: 0,
               datetime: DateTimeUtils.from_iso8601!("2017-05-17 00:00:00.000000Z")
             },
             %{
               active_addresses: 100,
               datetime: DateTimeUtils.from_iso8601!("2017-05-18 00:00:00.000000Z")
             }
           ]
  end

  test "daily active addresses for contract with no data return zeroes", context do
    assert {:ok, result} =
             DailyActiveAddresses.active_addresses(
               "non_existing_contract",
               context.datetime_from,
               context.datetime_to,
               "2d"
             )

    assert result == [
             %{
               active_addresses: 0,
               datetime: DateTimeUtils.from_iso8601!("2017-05-13 00:00:00.000000Z")
             },
             %{
               active_addresses: 0,
               datetime: DateTimeUtils.from_iso8601!("2017-05-15 00:00:00.000000Z")
             },
             %{
               active_addresses: 0,
               datetime: DateTimeUtils.from_iso8601!("2017-05-17 00:00:00.000000Z")
             }
           ]
  end

  test "daily active addresses average in interval", context do
    assert {:ok, result} =
             DailyActiveAddresses.active_addresses(
               context.contract,
               context.datetime_from,
               context.datetime_to,
               "7d"
             )

    assert result == [
             %{
               active_addresses: 1150,
               datetime: DateTimeUtils.from_iso8601!("2017-05-13 00:00:00.000000Z")
             }
           ]
  end

  test "daily active addresses wrong dates", context do
    assert {:ok, result} =
             DailyActiveAddresses.active_addresses(
               context.contract,
               context.datetime_to,
               context.datetime_from,
               "6h"
             )

    assert result == []
  end
end
