defmodule Sanbase.Model.LatestBtcWalletData do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.LatestBtcWalletData

  schema "latest_btc_wallet_data" do
    field :address, :string
    field :satoshi_balance, :decimal
    field :update_time, Ecto.DateTime
  end

  @doc false
  def changeset(%LatestBtcWalletData{} = latest_btc_wallet_data, attrs \\ %{}) do
    latest_btc_wallet_data
    |> cast(attrs, [:address, :satoshi_balance, :update_time])
    |> validate_required([:address, :satoshi_balance, :update_time])
    |> unique_constraint(:address)
  end
end
