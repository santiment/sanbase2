defmodule Sanbase.Notifications.Type do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.Notifications.Type

  schema "notification_type" do
    field(:name, :string)

    timestamps()
  end

  def changeset(%Type{} = type, attrs \\ %{}) do
    type
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
