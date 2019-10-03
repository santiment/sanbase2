defmodule Sanbase.TimescaleFactory do
  use ExMachina.Ecto, repo: Sanbase.TimescaleRepo

  alias Sanbase.Blockchain.{
    TokenAgeConsumed,
    TransactionVolume
  }

  @contract_address "0x1234"

  def token_age_consumed_factory() do
    %TokenAgeConsumed{
      contract_address: @contract_address,
      timestamp: DateTime.utc_now(),
      token_age_consumed: 1000.0
    }
  end

  def transaction_volume_factory() do
    %TransactionVolume{
      contract_address: @contract_address,
      timestamp: DateTime.utc_now(),
      transaction_volume: 1000.0
    }
  end
end
