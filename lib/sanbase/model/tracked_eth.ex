defmodule Sanbase.Model.TrackedEth do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.TrackedEth


  @primary_key{:address, :string, []}
  schema "tracked_eth" do
    # field :address, :string
  end

  @doc false
  def changeset(%TrackedEth{} = tracked_eth, attrs) do
    tracked_eth
    |> cast(attrs, [:address])
    |> validate_required([:address])
  end
end
