defmodule Sanbase.Accounts.LinkedUser do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Accounts.User

  schema "linked_users" do
    belongs_to(:user, User)
    belongs_to(:primary_user, User)
  end

  def changeset(%__MODULE__{} = lu, attrs) do
    lu
    |> cast(attrs, [:user_id, :primary_user_id])
    |> validate_required([:user_id, :primary_user_id])
    |> unique_constraint(:user_id)
  end

  def create(user_id, primary_user_id) do
    %__MODULE__{}
    |> changeset(%{user_id: user_id, primary_user_id: primary_user_id})
    |> Sanbase.Repo.insert()
  end

  def get_primary_user_id(user_id) do
    result =
      from(lu in __MODULE__,
        where: lu.user_id == ^user_id,
        select: lu.primary_user_id
      )
      |> Sanbase.Repo.one()

    case result do
      nil -> {:error, "No linked user found for user_id: #{user_id}"}
      primary_user_id -> {:ok, primary_user_id}
    end
  end
end
