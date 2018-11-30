defmodule Sanbase.Notifications.Type do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.Notifications.Type
  alias Sanbase.Repo

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

  def get_or_create(name) when is_binary(name) do
    Repo.get_by(Type, name: name)
    |> case do
      result = %Type{} ->
        result

      nil ->
        %Type{}
        |> Type.changeset(%{name: name})
        |> Repo.insert!()
    end
  end
end
