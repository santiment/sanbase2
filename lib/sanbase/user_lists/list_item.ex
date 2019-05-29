defmodule Sanbase.UserList.ListItem do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.UserList
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

  def get_projects(%{id: id}) do
    from(li in __MODULE__,
      where: li.user_list_id == ^id,
      preload: [:project]
    )
    |> Sanbase.Repo.all()
    |> Enum.map(& &1.project)
  end
end
