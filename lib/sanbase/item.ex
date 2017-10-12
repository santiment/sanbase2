defmodule Sanbase.Item do
  use Ecto.Schema

  schema "items" do
    field :name, :string

    timestamps()
  end
end
