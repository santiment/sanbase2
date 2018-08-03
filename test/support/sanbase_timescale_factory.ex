defmodule Sanbase.TimescaleFactory do
  use ExMachina.Ecto, repo: Sanbase.TimescaleRepo

  alias Sanbase.Blockchain.{
    BurnRate,
    DailyActiveAddresses,
    TransactionVolume
  }

  def burn_rate_factory() do
    %BurnRate{
      contract_address: "0x123",
      timestamp: DateTime.utc_now(),
      burn_rate: 1000.0
    }
  end

  def daily_active_addresses_factory() do
    %DailyActiveAddresses{
      contract_address: "0x123",
      timestamp: DateTime.utc_now(),
      active_addresses: 1000
    }
  end

  def transaction_volume_factory() do
    %TransactionVolume{
      contract_address: "0x123",
      timestamp: DateTime.utc_now(),
      transaction_volume: 1000.0
    }
  end
end
