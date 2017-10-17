defmodule Sanbase.Model.Country do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.Country


  @primary_key{:code, :string, []}
  schema "countries" do
    # field :code, :string
    field :orthodox, :boolean
    field :sinic, :boolean
    field :western, :boolean
  end

  @doc false
  def changeset(%Country{} = country, attrs \\ %{}) do
    country
    |> cast(attrs, [:code, :western, :orthodox, :sinic])
    |> validate_required([:code, :western, :orthodox, :sinic])
  end
end
