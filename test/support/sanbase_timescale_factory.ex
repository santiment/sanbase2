defmodule Sanbase.TimescaleFactory do
  use ExMachina.Ecto, repo: Sanbase.TimescaleRepo

  alias Sanbase.Blockchain.{
    BurnRate,
    DailyActiveAddresses,
    TransactionVolume,
    ExchangeFundsFlow,
    TokenCirculation
  }

  @contract_address "0x1234"

  def burn_rate_factory() do
    %BurnRate{
      contract_address: @contract_address,
      timestamp: DateTime.utc_now(),
      burn_rate: 1000.0
    }
  end

  def daily_active_addresses_factory() do
    %DailyActiveAddresses{
      contract_address: @contract_address,
      timestamp: DateTime.utc_now(),
      active_addresses: 1000
    }
  end

  def transaction_volume_factory() do
    %TransactionVolume{
      contract_address: @contract_address,
      timestamp: DateTime.utc_now(),
      transaction_volume: 1000.0
    }
  end

  def exchange_funds_flow_factory() do
    %ExchangeFundsFlow{
      contract_address: @contract_address,
      timestamp: DateTime.utc_now(),
      incoming_exchange_funds: 1000,
      outgoing_exchange_funds: 1000
    }
  end

  def token_circulation_factory() do
    %TokenCirculation{
      contract_address: @contract_address,
      timestamp: DateTime.utc_now(),
      less_than_a_day: 1000.0
    }
  end
end
