defmodule Sanbase.Blockchain.ExchangeFundsFlowTest do
  use Sanbase.DataCase, async: true
  @moduletag checkout_repo: Sanbase.TimescaleRepo
  @moduletag timescaledb: true

  import Sanbase.TimescaleFactory

  alias Sanbase.Blockchain.ExchangeFundsFlow
  alias Sanbase.DateTimeUtils

  setup do
    contract = "0x" <> Sanbase.TestUtils.random_string()

    datetime1 = DateTime.from_naive!(~N[2017-05-13 00:00:00], "Etc/UTC")
    datetime2 = DateTime.from_naive!(~N[2017-05-14 23:30:30], "Etc/UTC")
    datetime3 = DateTime.from_naive!(~N[2017-05-15 10:10:00], "Etc/UTC")
    datetime4 = DateTime.from_naive!(~N[2017-05-16 10:54:22], "Etc/UTC")

    insert(:exchange_funds_flow, %{
      contract_address: contract,
      timestamp: datetime1,
      incoming_exchange_funds: 1500.0,
      outgoing_exchange_funds: 500.0
    })

    insert(:exchange_funds_flow, %{
      contract_address: contract,
      timestamp: datetime2,
      incoming_exchange_funds: 255.0,
      outgoing_exchange_funds: 500.0
    })

    insert(:exchange_funds_flow, %{
      contract_address: contract,
      timestamp: datetime3,
      incoming_exchange_funds: 150.0,
      outgoing_exchange_funds: 5000.0
    })

    insert(:exchange_funds_flow, %{
      contract_address: contract,
      timestamp: datetime4,
      incoming_exchange_funds: 4500.0,
      outgoing_exchange_funds: 550.0
    })

    %{
      contract: contract,
      datetime_from: datetime1,
      datetime_to: datetime4
    }
  end

  test "exchange funds flow fill gaps", context do
    assert {:ok, result} =
             ExchangeFundsFlow.transactions_in_out_difference(
               context.contract,
               context.datetime_from,
               context.datetime_to,
               "12h"
             )

    assert result == [
             %{
               datetime: DateTimeUtils.from_iso8601!("2017-05-13 00:00:00.00Z"),
               exchange_funds_flow: 1000.0
             },
             %{
               datetime: DateTimeUtils.from_iso8601!("2017-05-13 12:00:00.00Z"),
               exchange_funds_flow: 0.0
             },
             %{
               datetime: DateTimeUtils.from_iso8601!("2017-05-14 00:00:00.00Z"),
               exchange_funds_flow: 0.0
             },
             %{
               datetime: DateTimeUtils.from_iso8601!("2017-05-14 12:00:00.00Z"),
               exchange_funds_flow: -245.0
             },
             %{
               datetime: DateTimeUtils.from_iso8601!("2017-05-15 00:00:00.00Z"),
               exchange_funds_flow: -4850.0
             },
             %{
               datetime: DateTimeUtils.from_iso8601!("2017-05-15 12:00:00.00Z"),
               exchange_funds_flow: 0.0
             },
             %{
               datetime: DateTimeUtils.from_iso8601!("2017-05-16 00:00:00.00Z"),
               exchange_funds_flow: 3950.0
             }
           ]
  end

  test "exchange funds flow for contract with no data return zeroes", context do
    assert {:ok, result} =
             ExchangeFundsFlow.transactions_in_out_difference(
               "non_existing_contract",
               context.datetime_from,
               context.datetime_to,
               "18h"
             )

    assert result == [
             %{
               datetime: DateTimeUtils.from_iso8601!("2017-05-13 00:00:00.00Z"),
               exchange_funds_flow: 0.0
             },
             %{
               datetime: DateTimeUtils.from_iso8601!("2017-05-13 18:00:00.00Z"),
               exchange_funds_flow: 0.0
             },
             %{
               datetime: DateTimeUtils.from_iso8601!("2017-05-14 12:00:00.00Z"),
               exchange_funds_flow: 0.0
             },
             %{
               datetime: DateTimeUtils.from_iso8601!("2017-05-15 06:00:00.00Z"),
               exchange_funds_flow: 0.0
             },
             %{
               datetime: DateTimeUtils.from_iso8601!("2017-05-16 00:00:00.00Z"),
               exchange_funds_flow: 0.0
             }
           ]
  end

  test "exchange funds flow sum in interval", context do
    assert {:ok, result} =
             ExchangeFundsFlow.transactions_in_out_difference(
               context.contract,
               context.datetime_from,
               context.datetime_to,
               "7d"
             )

    assert result == [
             %{
               exchange_funds_flow: -145.0,
               datetime: DateTimeUtils.from_iso8601!("2017-05-13 00:00:00.00Z")
             }
           ]
  end

  test "exchange funds flow wrong dates", context do
    assert {:ok, result} =
             ExchangeFundsFlow.transactions_in_out_difference(
               context.contract,
               context.datetime_to,
               context.datetime_from,
               "6h"
             )

    assert result == []
  end
end
