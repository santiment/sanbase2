defmodule Sanbase.UserList do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias __MODULE__
  alias Sanbase.Auth.User
  alias Sanbase.UserList.ListItem
  alias Sanbase.Repo
  alias Sanbase.Timeline.TimelineEvent

  schema "user_lists" do
    field(:name, :string)
    field(:is_public, :boolean, default: false)
    field(:color, ColorEnum, default: :none)

    belongs_to(:user, User)
    has_one(:featured_item, Sanbase.FeaturedItem, on_delete: :delete_all)
    has_many(:list_items, ListItem, on_delete: :delete_all, on_replace: :delete)
    has_many(:timeline_events, TimelineEvent, on_delete: :delete_all)

    timestamps()
  end

  # ex_admin needs changeset function
  def changeset(user_list, attrs \\ %{}) do
    update_changeset(user_list, attrs)
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
    from(ul in UserList, where: ul.id == ^id, preload: [:list_items]) |> Repo.one()
  end

  def create_user_list(%User{id: user_id} = _user, params \\ %{}) do
    %UserList{}
    |> create_changeset(Map.merge(params, %{user_id: user_id}))
    |> Repo.insert()
  end

  def update_user_list(%{id: id} = params) do
    params = update_list_items_params(params, id)
    watchlist = UserList.by_id(id)
    changeset = watchlist |> update_changeset(params)

    if watchlist.is_public and Map.get(params, :list_items) do
      Repo.update(changeset)
      |> log_timeline_event()
    else
      Repo.update(changeset)
    end
  end

  defp log_timeline_event(result) do
    case result do
      {:ok, watchlist} ->
        Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
          TimelineEvent.create_event(watchlist, %{
            event_type: TimelineEvent.update_watchlist_type(),
            user_id: watchlist.user_id
          })
        end)

        {:ok, watchlist}

      {:error, changeset} ->
        {:error, changeset}
    end
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

  def user_list(user_list_id, %User{id: id}) do
    query =
      case id do
        nil ->
          from(ul in UserList,
            where: ul.is_public == true,
            preload: [:list_items]
          )

        _ ->
          from(ul in UserList,
            where: ul.is_public == true or ul.user_id == ^id,
            preload: [:list_items]
          )
      end

    result = Repo.get(query, user_list_id)

    {:ok, result}
  end

  defp update_list_items_params(params, id) do
    list_items = Map.get(params, :list_items)

    case list_items do
      nil ->
        params

      list_items ->
        list_items =
          list_items
          |> Enum.map(fn item -> %{project_id: item.project_id, user_list_id: id} end)

        Map.replace!(params, :list_items, list_items)
    end
  end
end
