defmodule Sanbase.UserLists.ListItem do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.UserLists.UserList
  alias Sanbase.Model.Project

  @primary_key false
  schema "list_items" do
    belongs_to(:project, Project, primary_key: true)
    belongs_to(:user_list, UserList, primary_key: true)
  end

  def changeset(list_item, attrs \\ %{}) do
    list_item
    |> cast(attrs, [:project_id, :user_list_id])
    |> validate_required([:project_id, :user_list_id])
  end
end
