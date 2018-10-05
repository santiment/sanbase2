defmodule Sanbase.Blockchain.BurnRateTest do
  use Sanbase.DataCase, async: true
  @moduletag checkout_repo: Sanbase.TimescaleRepo
  @moduletag timescaledb: true

  import Sanbase.TimescaleFactory

  alias Sanbase.Blockchain.BurnRate
  alias Sanbase.DateTimeUtils

  setup do
    contract = "0x" <> Sanbase.TestUtils.random_string()

    datetime1 = DateTime.from_naive!(~N[2017-05-13 00:00:00], "Etc/UTC")
    datetime2 = DateTime.from_naive!(~N[2017-05-14 00:00:00], "Etc/UTC")

    insert(:burn_rate, %{contract_address: contract, timestamp: datetime1, burn_rate: 500.0})
    insert(:burn_rate, %{contract_address: contract, timestamp: datetime2, burn_rate: 1500.0})

    %{
      contract: contract,
      datetime_from: datetime1,
      datetime_to: datetime2
    }
  end

  test "transaction volume fill gaps", context do
    assert {:ok, result} =
             BurnRate.burn_rate(
               context.contract,
               context.datetime_from,
               context.datetime_to,
               "6h"
             )

    assert result == [
             %{
               burn_rate: 500.0,
               datetime: DateTimeUtils.from_iso8601!("2017-05-13 00:00:00Z")
             },
             %{
               burn_rate: 0.0,
               datetime: DateTimeUtils.from_iso8601!("2017-05-13 06:00:00Z")
             },
             %{
               burn_rate: 0.0,
               datetime: DateTimeUtils.from_iso8601!("2017-05-13 12:00:00Z")
             },
             %{
               burn_rate: 0.0,
               datetime: DateTimeUtils.from_iso8601!("2017-05-13 18:00:00Z")
             },
             %{
               burn_rate: 1.5e3,
               datetime: DateTimeUtils.from_iso8601!("2017-05-14 00:00:00Z")
             }
           ]
  end

  test "transaction volume for contract with no data return zeroes", context do
    assert {:ok, result} =
             BurnRate.burn_rate(
               "non_existing_contract",
               context.datetime_from,
               context.datetime_to,
               "12h"
             )

    assert result == [
             %{
               burn_rate: 0.0,
               datetime: DateTimeUtils.from_iso8601!("2017-05-13 00:00:00Z")
             },
             %{
               burn_rate: 0.0,
               datetime: DateTimeUtils.from_iso8601!("2017-05-13 12:00:00Z")
             },
             %{
               burn_rate: 0.0,
               datetime: DateTimeUtils.from_iso8601!("2017-05-14 00:00:00Z")
             }
           ]
  end

  test "transaction volume sum in interval", context do
    assert {:ok, result} =
             BurnRate.burn_rate(
               context.contract,
               context.datetime_from,
               context.datetime_to,
               "2d"
             )

    assert result == [
             %{
               burn_rate: 2000.0,
               datetime: DateTimeUtils.from_iso8601!("2017-05-13 00:00:00Z")
             }
           ]
  end

  test "transaction volume wrong dates", context do
    assert {:ok, result} =
             BurnRate.burn_rate(
               context.contract,
               context.datetime_to,
               context.datetime_from,
               "6h"
             )

    assert result == []
  end
end
