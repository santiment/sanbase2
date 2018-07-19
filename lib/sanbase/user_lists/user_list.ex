defmodule Sanbase.UserLists.UserList do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias __MODULE__
  alias Sanbase.Auth.User
  alias Sanbase.UserLists.ListItem
  alias Sanbase.Repo

  schema "user_lists" do
    field(:name, :string)
    field(:is_public, :boolean, default: false)
    field(:color, ColorEnum, default: :none)

    belongs_to(:user, User)
    has_many(:list_items, ListItem, on_delete: :delete_all, on_replace: :delete)

    timestamps()
  end

  def create_changeset(%UserList{} = user_list, attrs \\ %{}) do
    user_list
    |> cast(attrs, [:user_id, :name, :is_public, :color])
    |> validate_required([:name, :user_id])
  end

  def update_changeset(%UserList{id: _id} = user_list, attrs \\ %{}) do
    user_list
    |> cast(attrs, [:name, :is_public, :color])
    |> cast_assoc(:list_items)
    |> validate_required([:name])
  end

  def by_id(id) do
    Repo.get!(UserList, id)
  end

  def create_user_list(%User{id: user_id} = _user, params \\ %{}) do
    %UserList{}
    |> create_changeset(Map.merge(params, %{user_id: user_id}))
    |> Repo.insert()
  end

  def update_user_list(%{id: id} = params) do
    params = update_list_items_params(params, id)

    UserList.by_id(id)
    |> Repo.preload(:list_items)
    |> update_changeset(params)
    |> Repo.update()
  end

  def remove_user_list(%{id: id}) do
    UserList.by_id(id)
    |> Repo.delete()
  end

  def fetch_user_lists(%User{id: id} = _user) do
    query =
      from(
        ul in UserList,
        where: ul.user_id == ^id
      )

    {:ok, Repo.all(query) |> Repo.preload(:list_items)}
  end

  def fetch_public_user_lists(%User{id: id} = _user) do
    query =
      from(
        ul in UserList,
        where: ul.user_id == ^id and ul.is_public == true
      )

    {:ok, Repo.all(query) |> Repo.preload(:list_items)}
  end

  def fetch_all_public_lists() do
    query =
      from(
        ul in UserList,
        where: ul.is_public == true
      )

    {:ok, Repo.all(query) |> Repo.preload(:list_items)}
  end

  defp update_list_items_params(params, id) do
    list_items = Map.get(params, :list_items, [])

    list_items =
      list_items
      |> Enum.reject(&is_nil/1)
      |> Enum.map(fn item ->
        %{project_id: item.project_id, user_list_id: id}
      end)

    case list_items do
      [] ->
        Map.delete(params, :list_items)

      list_items ->
        Map.delete(params, :list_items)
        put_in(params[:list_items], list_items)
    end
  end
end
