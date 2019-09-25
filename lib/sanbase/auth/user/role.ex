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

defmodule Sanbase.Auth.UserRole do
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Auth.{User, Role}

  @primary_key false
  schema "user_roles" do
    belongs_to(:user, User, primary_key: true)
    belongs_to(:role, Role, primary_key: true)
    timestamps()
  end

  def changeset(%__MODULE__{} = user_role, attrs \\ %{}) do
    user_role
    |> cast(attrs, [:user_id, :role_id])
    |> unique_constraint(:user, name: :user_roles_user_id_role_id_index)
  end
end
