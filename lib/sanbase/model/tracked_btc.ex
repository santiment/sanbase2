defmodule Sanbase.Model.TrackedBtc do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.TrackedBtc


  @primary_key{:address, :string, []}
  schema "tracked_btc" do
    # field :address, :string
  end

  @doc false
  def changeset(%TrackedBtc{} = tracked_btc, attrs) do
    tracked_btc
    |> cast(attrs, [:address])
    |> validate_required([:address])
  end
end
