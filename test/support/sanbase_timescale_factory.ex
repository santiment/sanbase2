defmodule Sanbase.TimescaleFactory do
  use ExMachina.Ecto, repo: Sanbase.TimescaleRepo

  alias Sanbase.Blockchain.{
    TransactionVolume
  }

  @contract_address "0x1234"

  def transaction_volume_factory() do
    %TransactionVolume{
      contract_address: @contract_address,
      timestamp: DateTime.utc_now(),
      transaction_volume: 1000.0
    }
  end
end
