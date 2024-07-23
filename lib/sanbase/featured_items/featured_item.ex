defmodule Sanbase.FeaturedItem do
  @moduledoc ~s"""
  Module for marking insights, watchlists and user triggers as featured.
  Featured items are meant to be used by the frontend to show them in a special way.
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Insight.Post
  alias Sanbase.UserList
  alias Sanbase.Alert.UserTrigger
  alias Sanbase.Chart.Configuration, as: ChartConfiguration
  alias Sanbase.TableConfiguration
  alias Sanbase.Dashboards.Dashboard
  alias Sanbase.Queries.Query

  @table "featured_items"
  schema @table do
    belongs_to(:post, Post)
    belongs_to(:user_list, UserList)
    belongs_to(:user_trigger, UserTrigger)
    belongs_to(:chart_configuration, ChartConfiguration)
    belongs_to(:table_configuration, TableConfiguration)
    belongs_to(:dashboard, Dashboard)
    belongs_to(:query, Query)

    timestamps()
  end

  @doc ~s"""
  Changeset for the FeaturedItem module.
  There is a database check that exactly one of `post_id`, `user_list_id` and
  `user_trigger_id` fields is set
  """
  def changeset(%__MODULE__{} = featured_items, attrs \\ %{}) do
    featured_items
    |> cast(attrs, [
      :post_id,
      :user_list_id,
      :user_trigger_id,
      :chart_configuration_id,
      :table_configuration_id,
      :dashboard_id,
      :query_id
    ])
    |> unique_constraint(:post_id)
    |> unique_constraint(:user_list_id)
    |> unique_constraint(:user_trigger_id)
    |> unique_constraint(:chart_configuration_id)
    |> unique_constraint(:table_configuration_id)
    |> unique_constraint(:dashboard_id)
    |> unique_constraint(:query_id)
    |> check_constraint(:one_featured_item_per_row, name: :only_one_fk)
  end

  def insights(opts \\ []) do
    insights_query()
    |> join(:inner, [fi], fi in assoc(fi, :post))
    |> where(
      [_fi, post],
      post.ready_state == ^Post.published() and post.state == ^Post.approved_state()
    )
    |> order_by([fi, _post], desc: fi.inserted_at, desc: fi.id)
    |> Sanbase.Entity.paginate(opts)
    |> select([fi, post], post)
    |> Repo.all()
    |> Repo.preload([:user, :tags])
  end

  def watchlists(args \\ %{}) do
    type = Map.get(args, :type, :project)
    is_screener = Map.get(args, :is_screener, false)

    watchlists_query()
    |> join(:inner, [fi], fi in assoc(fi, :user_list), as: :user_list)
    |> where([_fi, user_list: ul], ul.type == ^type)
    |> where([_fi, user_list: ul], ul.is_screener == ^is_screener)
    |> select([_fi, user_list: ul], ul)
    |> Repo.all()
    |> Repo.preload([:user, :list_items])
  end

  def user_triggers() do
    user_triggers_query()
    |> join(:inner, [fi], fi in assoc(fi, :user_trigger), as: :user_trigger)
    |> select([_fi, user_trigger: ut], ut)
    |> Repo.all()
    |> Repo.preload([:user, :tags])
  end

  def chart_configurations() do
    chart_configurations_query()
    |> join(:inner, [fi], fi in assoc(fi, :chart_configuration), as: :chart_configuration)
    |> select([_fi, chart_configuration: config], config)
    |> Repo.all()
  end

  def table_configurations() do
    table_configurations_query()
    |> join(:inner, [fi], fi in assoc(fi, :table_configuration), as: :table_configuration)
    |> select([_fi, table_configuration: config], config)
    |> Repo.all()
  end

  def dashboards() do
    dashboards_query()
    |> join(:inner, [fi], fi in assoc(fi, :dashboard), as: :dashboard)
    |> order_by([fi, _], desc: fi.inserted_at, desc: fi.id)
    |> select([_fi, dashboard: dashboard], dashboard)
    |> Repo.all()
    |> Repo.preload([:user])
  end

  def queries() do
    queries_query()
    |> join(:inner, [fi], fi in assoc(fi, :query), as: :query)
    |> order_by([fi, _], desc: fi.inserted_at, desc: fi.id)
    # TODO: If we name the binding here `query`, it gives a strange error
    |> select([_fi, query: q], q)
    |> Repo.all()
    |> Repo.preload([:user])
  end

  @doc ~s"""
  Mark the insight, watchlist or user trigger as featured or not.

  Update the record for the insight. If it the second argument is `false` any
  present record will be deleted. If the second argument is `true` a new record
  will be created if it does not exist
  """
  @spec update_item(
          %Post{} | %UserList{} | %UserTrigger{} | %ChartConfiguration{} | %TableConfiguration{},
          boolean
        ) ::
          :ok | {:error, Ecto.Changeset.t()}
  def update_item(%Post{} = post, featured?) do
    case Post.is_published?(post) || featured? == false do
      true -> update_item(:post_id, post.id, featured?)
      false -> {:error, "Not published post cannot be made featured."}
    end
  end

  def update_item(%UserList{} = user_list, featured?) do
    case UserList.public?(user_list) || featured? == false do
      true -> update_item(:user_list_id, user_list.id, featured?)
      false -> {:error, "Private watchlists cannot be made featured."}
    end
  end

  def update_item(%UserTrigger{} = user_trigger, featured?) do
    case UserTrigger.public?(user_trigger) || featured? == false do
      true -> update_item(:user_trigger_id, user_trigger.id, featured?)
      false -> {:error, "Private user triggers cannot be made featured."}
    end
  end

  def update_item(%ChartConfiguration{} = configuration, featured?) do
    case ChartConfiguration.public?(configuration) || featured? == false do
      true -> update_item(:chart_configuration_id, configuration.id, featured?)
      false -> {:error, "Private chart configurations cannot be made featured."}
    end
  end

  def update_item(%TableConfiguration{} = configuration, featured?) do
    case TableConfiguration.public?(configuration) || featured? == false do
      true -> update_item(:table_configuration_id, configuration.id, featured?)
      false -> {:error, "Private table configurations cannot be made featured."}
    end
  end

  def update_item(%Dashboard{} = dashboard, featured?) do
    case Dashboard.public?(dashboard) || featured? == false do
      true -> update_item(:dashboard_id, dashboard.id, featured?)
      false -> {:error, "Private table dashboards cannot be made featured."}
    end
  end

  def update_item(%Query{} = query, featured?) do
    case Query.public?(query) || featured? == false do
      true -> update_item(:query_id, query.id, featured?)
      false -> {:error, "Private table queries cannot be made featured."}
    end
  end

  # Private functions

  defp update_item(type, id, false) do
    from(fi in __MODULE__) |> where(^[{type, id}]) |> Repo.delete_all()
    :ok
  end

  defp update_item(type, id, true) do
    Repo.get_by(__MODULE__, [{type, id}])
    |> case do
      nil ->
        case %__MODULE__{} |> changeset(%{type => id}) |> Repo.insert() do
          {:ok, _} -> :ok
          error -> error
        end

      _result ->
        :ok
    end
  end

  defp insights_query(), do: from(fi in __MODULE__, where: not is_nil(fi.post_id))
  defp watchlists_query(), do: from(fi in __MODULE__, where: not is_nil(fi.user_list_id))
  defp user_triggers_query(), do: from(fi in __MODULE__, where: not is_nil(fi.user_trigger_id))
  defp dashboards_query(), do: from(fi in __MODULE__, where: not is_nil(fi.dashboard_id))
  defp queries_query(), do: from(fi in __MODULE__, where: not is_nil(fi.query_id))

  defp chart_configurations_query(),
    do: from(fi in __MODULE__, where: not is_nil(fi.chart_configuration_id))

  defp table_configurations_query(),
    do: from(fi in __MODULE__, where: not is_nil(fi.table_configuration_id))
end
