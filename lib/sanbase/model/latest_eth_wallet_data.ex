defmodule Sanbase.Model.LatestEthWalletData do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.LatestEthWalletData


  @primary_key{:address, :string, []}
  schema "latest_eth_wallet_data" do
    field :balance, :float
    field :last_incoming, :naive_datetime
    field :last_outgoing, :naive_datetime
    field :tx_in, :float
    field :tx_out, :float
    field :update_time, :naive_datetime
  end

  @doc false
  def changeset(%LatestEthWalletData{} = latest_eth_wallet_data, attrs \\ %{}) do
    latest_eth_wallet_data
    |> cast(attrs, [:address, :balance, :update_time, :last_incoming, :last_outgoing, :tx_in, :tx_out])
    |> validate_required([:address, :balance, :update_time])
  end
end
