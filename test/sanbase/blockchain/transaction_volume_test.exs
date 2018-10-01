defmodule Sanbase.Blockchain.TransactionVolumeTest do
  use Sanbase.DataCase, async: true
  @moduletag checkout_repo: Sanbase.TimescaleRepo
  @moduletag timescaledb: true

  import Sanbase.TimescaleFactory

  alias Sanbase.Blockchain.TransactionVolume
  alias Sanbase.DateTimeUtils

  setup do
    contract1 = "0x" <> Sanbase.TestUtils.random_string()

    datetime1 = DateTime.from_naive!(~N[2017-05-13 00:00:00], "Etc/UTC")
    datetime2 = DateTime.from_naive!(~N[2017-05-14 23:30:30], "Etc/UTC")
    datetime3 = DateTime.from_naive!(~N[2017-05-15 10:10:00], "Etc/UTC")
    datetime4 = DateTime.from_naive!(~N[2017-05-16 10:54:22], "Etc/UTC")

    insert(:transaction_volume, %{
      contract_address: contract1,
      timestamp: datetime1,
      transaction_volume: 500.0
    })

    insert(:transaction_volume, %{
      contract_address: contract1,
      timestamp: datetime2,
      transaction_volume: 1500.0
    })

    insert(:transaction_volume, %{
      contract_address: contract1,
      timestamp: datetime3,
      transaction_volume: 5000.0
    })

    insert(:transaction_volume, %{
      contract_address: contract1,
      timestamp: datetime4,
      transaction_volume: 100.0
    })

    %{
      contract: contract1,
      datetime_from: datetime1,
      datetime_to: datetime4
    }
  end

  test "burn rate fill gaps", context do
    assert {:ok, result} =
             TransactionVolume.transaction_volume(
               context.contract,
               context.datetime_from,
               context.datetime_to,
               "12h"
             )

    assert result == [
             %{
               datetime: DateTimeUtils.from_iso8601!("2017-05-13 00:00:00Z"),
               transaction_volume: 500.0
             },
             %{
               datetime: DateTimeUtils.from_iso8601!("2017-05-13 12:00:00Z"),
               transaction_volume: 0.0
             },
             %{
               datetime: DateTimeUtils.from_iso8601!("2017-05-14 00:00:00Z"),
               transaction_volume: 0.0
             },
             %{
               datetime: DateTimeUtils.from_iso8601!("2017-05-14 12:00:00Z"),
               transaction_volume: 1.5e3
             },
             %{
               datetime: DateTimeUtils.from_iso8601!("2017-05-15 00:00:00Z"),
               transaction_volume: 5.0e3
             },
             %{
               datetime: DateTimeUtils.from_iso8601!("2017-05-15 12:00:00Z"),
               transaction_volume: 0.0
             },
             %{
               datetime: DateTimeUtils.from_iso8601!("2017-05-16 00:00:00Z"),
               transaction_volume: 100.0
             }
           ]
  end

  test "burn rate for contract with no data return zeroes", context do
    assert {:ok, result} =
             TransactionVolume.transaction_volume(
               "non_existing_contract",
               context.datetime_from,
               context.datetime_to,
               "18h"
             )

    assert result == [
             %{
               datetime: DateTimeUtils.from_iso8601!("2017-05-13 00:00:00Z"),
               transaction_volume: 0.0
             },
             %{
               datetime: DateTimeUtils.from_iso8601!("2017-05-13 18:00:00Z"),
               transaction_volume: 0.0
             },
             %{
               datetime: DateTimeUtils.from_iso8601!("2017-05-14 12:00:00Z"),
               transaction_volume: 0.0
             },
             %{
               datetime: DateTimeUtils.from_iso8601!("2017-05-15 06:00:00Z"),
               transaction_volume: 0.0
             },
             %{
               datetime: DateTimeUtils.from_iso8601!("2017-05-16 00:00:00Z"),
               transaction_volume: 0.0
             }
           ]
  end

  test "burn rate sum in interval", context do
    assert {:ok, result} =
             TransactionVolume.transaction_volume(
               context.contract,
               context.datetime_from,
               context.datetime_to,
               "7d"
             )

    assert result == [
             %{
               transaction_volume: 7100.0,
               datetime: DateTimeUtils.from_iso8601!("2017-05-13 00:00:00Z")
             }
           ]
  end

  test "burn rate wrong dates", context do
    assert {:ok, result} =
             TransactionVolume.transaction_volume(
               context.contract,
               context.datetime_to,
               context.datetime_from,
               "6h"
             )

    assert result == []
  end
end
