defmodule Sanbase.Model.CryptocomparePrices do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.CryptocomparePrices
  alias Sanbase.Model.Project


  schema "cryptocompare_prices" do
    field :id_from, :string
    field :id_to, :string
    field :price, :decimal
  end

  @doc false
  def changeset(%CryptocomparePrices{} = prices, attrs \\ %{}) do
    prices
    |> cast(attrs, [:id_from, :id_to, :price])
    |> validate_required([:id_from, :id_to])
    |> unique_constraint(:id_from_to, name: :cryptocompare_id_from_to_index)
  end
end
