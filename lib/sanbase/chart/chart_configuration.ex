defmodule Sanbase.Chart.Configuration do
  @moduledoc false
  @behaviour Sanbase.Entity.Behaviour

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query
  import Sanbase.Utils.Transform, only: [to_bang: 1]

  alias Sanbase.Entity.Query
  alias Sanbase.Insight.Post
  alias Sanbase.Repo

  schema "chart_configurations" do
    field(:title, :string)
    field(:description, :string)
    field(:is_public, :boolean, default: false)
    field(:is_deleted, :boolean, default: false)
    field(:is_hidden, :boolean, default: false)

    field(:metrics, {:array, :string}, default: [])
    field(:metrics_json, :map, default: %{})
    field(:anomalies, {:array, :string}, default: [])
    field(:queries, :map, default: %{})
    field(:drawings, :map, default: %{})
    field(:options, :map, default: %{})

    has_one(:featured_item, Sanbase.FeaturedItem,
      on_delete: :delete_all,
      foreign_key: :chart_configuration_id
    )

    has_many(:votes, Sanbase.Vote, on_delete: :delete_all, foreign_key: :chart_configuration_id)

    has_one(:shared_access_token, __MODULE__.SharedAccessToken,
      foreign_key: :chart_configuration_id,
      on_delete: :delete_all
    )

    belongs_to(:post, Post)
    belongs_to(:user, Sanbase.Accounts.User)
    belongs_to(:project, Sanbase.Project)

    has_many(:chart_events, Post,
      foreign_key: :chart_configuration_for_event_id,
      where: [is_chart_event: true]
    )

    # Virtual fields
    field(:views, :integer, virtual: true, default: 0)
    field(:is_featured, :boolean, virtual: true)

    timestamps()
  end

  def changeset(%__MODULE__{} = conf, attrs \\ %{}) do
    conf
    |> cast(attrs, [
      :title,
      :description,
      :is_public,
      :is_deleted,
      :is_hidden,
      :metrics,
      :metrics_json,
      :anomalies,
      :queries,
      :drawings,
      :options,
      :user_id,
      :project_id,
      :post_id
    ])
    |> validate_required([:user_id, :project_id])
  end

  @impl Sanbase.Entity.Behaviour
  def get_visibility_data(id) do
    Query.default_get_visibility_data(__MODULE__, :chart_configration, id)
  end

  @impl Sanbase.Entity.Behaviour
  def by_id!(id, opts), do: id |> by_id(opts) |> to_bang()

  @impl Sanbase.Entity.Behaviour
  def by_id(id, opts) do
    querying_user_id = Keyword.get(opts, :querying_user_id)
    get_chart_configuration(id, querying_user_id, opts)
  end

  @impl Sanbase.Entity.Behaviour
  def by_ids!(ids, opts), do: ids |> by_ids(opts) |> to_bang()

  @impl Sanbase.Entity.Behaviour
  def by_ids(config_ids, opts) do
    preload = Keyword.get(opts, :preload, [:chart_events, :featured_item])

    result =
      from(
        conf in base_query(),
        where: conf.id in ^config_ids,
        preload: ^preload,
        order_by: fragment("array_position(?, ?::int)", ^config_ids, conf.id)
      )
      |> maybe_apply_only_with_user_access(opts)
      |> Repo.all()

    {:ok, result}
  end

  # The base of all the entity queries
  defp base_entity_ids_query(opts) do
    base_query()
    |> maybe_apply_projects_filter(opts)
    |> Query.maybe_filter_is_hidden(opts)
    |> Query.maybe_filter_min_title_length(opts, :title)
    |> Query.maybe_filter_min_description_length(opts, :description)
    |> Query.maybe_filter_is_featured_query(opts, :chart_configuration_id)
    |> Query.maybe_filter_by_users(opts)
    |> Query.maybe_filter_by_cursor(:inserted_at, opts)
    |> select([config], config.id)
  end

  @impl Sanbase.Entity.Behaviour
  def public_and_user_entity_ids_query(user_id, opts) do
    opts
    |> base_entity_ids_query()
    |> where([config], config.is_public == true or config.user_id == ^user_id)
  end

  @impl Sanbase.Entity.Behaviour
  def public_entity_ids_query(opts) do
    opts
    |> base_entity_ids_query()
    |> where([config], config.is_public == true)
  end

  @impl Sanbase.Entity.Behaviour
  def user_entity_ids_query(user_id, opts) do
    opts
    |> base_entity_ids_query()
    |> where([config], config.user_id == ^user_id)
  end

  def public?(%__MODULE__{is_public: is_public}), do: is_public

  def user_configurations(user_id, querying_user_id, project_id \\ nil) do
    user_id
    |> user_chart_configurations_query(querying_user_id, project_id)
    |> Repo.all()
  end

  def project_configurations(project_id, querying_user_id \\ nil) do
    project_id
    |> project_chart_configurations_query(querying_user_id)
    |> Repo.all()
  end

  def configurations(querying_user_id \\ nil) do
    base_query()
    |> accessible_by_user_query(querying_user_id)
    |> Repo.all()
  end

  def create(%{} = attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  def update(config_id, user_id, attrs) do
    case get_chart_configuration_if_owner(config_id, user_id) do
      {:ok, %__MODULE__{} = conf} ->
        conf
        |> changeset(attrs)
        |> Repo.update()

      {:error, error} ->
        {:error, "Cannot update chart configuration. Reason: #{inspect(error)}"}
    end
  end

  def delete(config_id, user_id) do
    case get_chart_configuration_if_owner(config_id, user_id) do
      {:ok, %__MODULE__{} = conf} ->
        Repo.delete(conf)

      {:error, error} ->
        {:error, "Cannot delete chart configuration. Reason: #{inspect(error)}"}
    end
  end

  # Private functions

  defp base_query(_opts \\ []) do
    from(conf in __MODULE__, where: conf.is_deleted != true)
  end

  defp get_chart_configuration(config_id, querying_user_id, opts) do
    preload = Keyword.get(opts, :preload, [:chart_events])

    query =
      from(
        conf in base_query(),
        where: conf.id == ^config_id,
        preload: ^preload
      )

    case Repo.one(query) do
      %__MODULE__{user_id: user_id, is_public: is_public} = conf
      when user_id == querying_user_id or is_public == true ->
        {:ok, conf}

      _ ->
        {:error, "Chart configuration with id #{config_id} does not exist or is private."}
    end
  end

  defp get_chart_configuration_if_owner(config_id, user_id) do
    query =
      from(
        conf in base_query(),
        where: conf.id == ^config_id
      )

    case Repo.one(query) do
      %__MODULE__{user_id: ^user_id} = conf ->
        {:ok, conf}

      _ ->
        {:error, "Chart configuration with id #{config_id} does not exist or is private."}
    end
  end

  defp user_chart_configurations_query(user_id, querying_user_id, nil) do
    base_query()
    |> where([conf], conf.user_id == ^user_id)
    |> accessible_by_user_query(querying_user_id)
  end

  defp user_chart_configurations_query(user_id, querying_user_id, project_id) do
    project_id
    |> filter_by_project_query()
    |> where([conf], conf.user_id == ^user_id)
    |> accessible_by_user_query(querying_user_id)
  end

  defp project_chart_configurations_query(project_id, querying_user_id) do
    project_id
    |> filter_by_project_query()
    |> accessible_by_user_query(querying_user_id)
  end

  defp filter_by_project_query(project_id) when not is_nil(project_id) do
    where(base_query(), [conf], conf.project_id == ^project_id)
  end

  defp accessible_by_user_query(query, nil) do
    where(query, [conf], conf.is_public == true)
  end

  defp accessible_by_user_query(query, querying_user_id) do
    where(query, [conf], conf.is_public == true or conf.user_id == ^querying_user_id)
  end

  defp maybe_apply_projects_filter(query, opts) do
    case Keyword.get(opts, :filter) do
      %{project_ids: project_ids} ->
        where(query, [config], config.project_id in ^project_ids)

      _ ->
        query
    end
  end

  defp maybe_apply_only_with_user_access(query, opts) do
    case Keyword.get(opts, :user_id_has_access) do
      user_id when is_integer(user_id) ->
        where(query, [config], config.user_id == ^user_id or config.is_public == true)

      _ ->
        query
    end
  end
end
