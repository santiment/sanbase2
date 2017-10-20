defmodule Sanbase.Model.TrackedBtc do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.TrackedBtc


  schema "tracked_btc" do
    field :address, :string
  end

  @doc false
  def changeset(%TrackedBtc{} = tracked_btc, attrs \\ %{}) do
    tracked_btc
    |> cast(attrs, [:address])
    |> validate_required([:address])
    |> unique_constraint(:address)
  end
end
