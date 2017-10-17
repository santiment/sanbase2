defmodule Sanbase.Model.Currency do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.Currency


  @primary_key{:code, :string, []}
  schema "currencies" do
    # field :code, :string
  end

  @doc false
  def changeset(%Currency{} = currency, attrs \\ %{}) do
    currency
    |> cast(attrs, [:code])
    |> validate_required([:code])
  end
end
