defmodule Sanbase.UserLists.ListItem do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias __MODULE__
  alias Sanbase.UserLists.UserList
  alias Sanbase.Model.Project
  alias Sanbase.Repo

  @primary_key false
  schema "list_items" do
    belongs_to(:project, Project, primary_key: true)
    belongs_to(:user_list, UserList, primary_key: true)
  end

  def changeset(list_item, attrs \\ %{}) do
    IO.inspect(attrs)

    list_item
    |> IO.inspect()
    |> cast(attrs, [:project_id, :user_list_id])
    |> validate_required([:project_id, :user_list_id])
  end
end
