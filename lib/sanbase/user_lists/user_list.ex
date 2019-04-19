defmodule Sanbase.UserList do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias __MODULE__
  alias Sanbase.Auth.User
  alias Sanbase.UserList.ListItem
  alias Sanbase.WatchlistFunction
  alias Sanbase.Repo

  schema "user_lists" do
    field(:name, :string)
    field(:is_public, :boolean, default: false)
    field(:color, ColorEnum, default: :none)
    field(:function, WatchlistFunction, default: %WatchlistFunction{})

    belongs_to(:user, User)
    has_one(:featured_item, Sanbase.FeaturedItem, on_delete: :delete_all)
    has_many(:list_items, ListItem, on_delete: :delete_all, on_replace: :delete)

    timestamps()
  end

  # ex_admin needs changeset function
  def changeset(user_list, attrs \\ %{}) do
    update_changeset(user_list, attrs)
  end

  def create_changeset(%__MODULE__{} = user_list, attrs \\ %{}) do
    user_list
    |> cast(attrs, [:user_id, :name, :is_public, :color, :function])
    |> validate_required([:name, :user_id])
  end

  def update_changeset(%__MODULE__{id: _id} = user_list, attrs \\ %{}) do
    user_list
    |> cast(attrs, [:name, :is_public, :color, :function])
    |> cast_assoc(:list_items)
    |> validate_required([:name])
  end

  def by_id(id) do
    from(ul in __MODULE__, where: ul.id == ^id, preload: [:list_items]) |> Repo.one()
  end

  def get_projects(%__MODULE__{function: fun} = user_list) do
    WatchlistFunction.evaluate(fun) ++ ListItem.get_projects(user_list)
  end

  def create_user_list(%User{id: user_id} = _user, params \\ %{}) do
    %__MODULE__{}
    |> create_changeset(Map.merge(params, %{user_id: user_id}))
    |> Repo.insert()
  end

  def update_user_list(%{id: id} = params) do
    params = update_list_items_params(params, id)

    by_id(id)
    |> Repo.preload(:list_items)
    |> update_changeset(params)
    |> Repo.update()
  end

  def remove_user_list(%{id: id}) do
    by_id(id) |> Repo.delete()
  end

  def fetch_user_lists(%User{id: id} = _user) do
    query = from(ul in __MODULE__, where: ul.user_id == ^id, preload: [:list_items])
    {:ok, Repo.all(query)}
  end

  def fetch_public_user_lists(%User{id: id} = _user) do
    query =
      from(ul in __MODULE__,
        where: ul.user_id == ^id and ul.is_public == true,
        preload: [:list_items]
      )

    {:ok, Repo.all(query)}
  end

  def fetch_all_public_lists() do
    query =
      from(
        ul in __MODULE__,
        where: ul.is_public == true,
        preload: [:list_items]
      )

    {:ok, Repo.all(query)}
  end

  def user_list(user_list_id, %User{id: id}) do
    query = user_list_query_by_user_id(id) |> preload(:list_items)
    {:ok, Repo.get(query, user_list_id)}
  end

  # Private functions

  defp user_list_query_by_user_id(nil) do
    from(dul in __MODULE__, where: dul.is_public == true)
  end

  defp user_list_query_by_user_id(user_id) when is_integer(user_id) and user_id > 0 do
    from(ul in __MODULE__, where: ul.is_public == true or ul.user_id == ^user_id)
  end

  defp update_list_items_params(%{list_items: list_items} = params, id)
       when is_list(list_items) do
    list_items =
      list_items
      |> Enum.map(fn item -> %{project_id: item.project_id, user_list_id: id} end)

    %{params | list_items: list_items}
  end

  defp update_list_items_params(params, _) when is_map(params), do: params
end
