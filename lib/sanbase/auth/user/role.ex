defmodule Sanbase.Auth.Role do
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Auth.User
  alias Sanbase.Repo

  schema "roles" do
    field(:name, :string)
    field(:code, :string)
  end

  def changeset(%__MODULE__{} = role, attrs \\ %{}) do
    role
    |> cast(attrs, [:name, :code])
    |> unique_constraint(:code)
  end

  def san_family_role_id() do
    Repo.get_by(__MODULE__, code: "san_family")
    |> Map.get(:id)
  end
end
