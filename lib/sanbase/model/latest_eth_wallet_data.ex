defmodule Sanbase.Model.LatestEthWalletData do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.LatestEthWalletData

  schema "latest_eth_wallet_data" do
    field(:address, :string)
    field(:balance, :decimal)
    field(:last_incoming, :naive_datetime)
    field(:last_outgoing, :naive_datetime)
    field(:tx_in, :decimal)
    field(:tx_out, :decimal)
    field(:update_time, :naive_datetime)
  end

  @doc false
  def changeset(%LatestEthWalletData{} = latest_eth_wallet_data, attrs \\ %{}) do
    latest_eth_wallet_data
    |> cast(attrs, [
      :address,
      :balance,
      :update_time,
      :last_incoming,
      :last_outgoing,
      :tx_in,
      :tx_out
    ])
    |> validate_required([:address, :balance, :update_time])
    |> update_change(:address, &String.downcase/1)
    |> unique_constraint(:address)
  end
end
