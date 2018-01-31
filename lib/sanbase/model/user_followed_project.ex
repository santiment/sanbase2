defmodule Sanbase.Model.UserFollowedProject do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.UserFollowedProject

  schema "user_followed_project" do
    field(:project_id, :integer)
    field(:user_id, :integer)
  end

  def changeset(%UserFollowedProject{} = user_projects, attrs \\ %{}) do
    user_projects
    |> cast(attrs, [:project_id, :user_id])
    |> validate_required([:project_id, :user_id])
    |> unique_constraint(:unique_pair, name: :projet_user_constraint)
  end
end
