defmodule Sanbase.Model.LatestBtcWalletData do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.LatestBtcWalletData


  @primary_key{:address, :string, []}
  schema "latest_btc_wallet_data" do
    # field :address, :string
    field :satoshi_balance, :float
    field :update_time, :naive_datetime
  end

  @doc false
  def changeset(%LatestBtcWalletData{} = latest_btc_wallet_data, attrs) do
    latest_btc_wallet_data
    |> cast(attrs, [:address, :satoshi_balance, :update_time])
    |> validate_required([:address, :satoshi_balance, :update_time])
  end
end
