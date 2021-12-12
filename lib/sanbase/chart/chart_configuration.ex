defmodule Sanbase.Chart.Configuration do
  @behaviour Sanbase.Entity.Behaviour

  use Ecto.Schema

  import Ecto.{Query, Changeset}
  import Sanbase.Utils.Transform, only: [to_bang: 1]

  alias Sanbase.Repo

  schema "chart_configurations" do
    field(:title, :string)
    field(:description, :string)
    field(:is_public, :boolean, default: false)

    field(:metrics, {:array, :string}, default: [])
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

    belongs_to(:post, Sanbase.Insight.Post)
    belongs_to(:user, Sanbase.Accounts.User)
    belongs_to(:project, Sanbase.Model.Project)

    has_many(:chart_events, Sanbase.Insight.Post,
      foreign_key: :chart_configuration_for_event_id,
      where: [is_chart_event: true]
    )

    timestamps()
  end

  def changeset(%__MODULE__{} = conf, attrs \\ %{}) do
    conf
    |> cast(attrs, [
      :title,
      :description,
      :is_public,
      :metrics,
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
  def by_id!(id, opts), do: by_id(id, opts) |> to_bang()

  @impl Sanbase.Entity.Behaviour
  def by_id(id, opts) do
    querying_user_id = Keyword.get(opts, :querying_user_id)
    get_chart_configuration(id, querying_user_id, opts)
  end

  @impl Sanbase.Entity.Behaviour
  def by_ids!(ids, opts), do: by_ids(ids, opts) |> to_bang()

  @impl Sanbase.Entity.Behaviour
  def by_ids(ids, opts), do: get_chart_configurations(ids, opts)

  @impl Sanbase.Entity.Behaviour
  def public_entity_ids_query(_opts) do
    from(config in __MODULE__, where: config.is_public == true)
    |> select([config], config.id)
  end

  def is_public?(%__MODULE__{is_public: is_public}), do: is_public

  def user_configurations(user_id, querying_user_id, project_id \\ nil) do
    user_chart_configurations_query(user_id, querying_user_id, project_id)
    |> Repo.all()
  end

  def project_configurations(project_id, querying_user_id \\ nil) do
    project_chart_configurations_query(project_id, querying_user_id)
    |> Repo.all()
  end

  def configurations(querying_user_id \\ nil) do
    __MODULE__
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
        conf
        |> Repo.delete()

      {:error, error} ->
        {:error, "Cannot delete chart configuration. Reason: #{inspect(error)}"}
    end
  end

  defp get_chart_configuration(config_id, querying_user_id, opts) do
    preload = Keyword.get(opts, :preload, [:chart_events])

    query =
      from(
        conf in __MODULE__,
        where: conf.id == ^config_id,
        preload: ^preload
      )

    case Repo.one(query) do
      %__MODULE__{user_id: user_id, is_public: is_public} = conf
      when user_id == querying_user_id or is_public == true ->
        {:ok, conf}

      %__MODULE__{} ->
        {:error, "Chart configuration with id #{config_id} is private."}

      nil ->
        {:error, "Chart configuration with id #{config_id} does not exist."}
    end
  end

  defp get_chart_configuration_if_owner(config_id, user_id) do
    case Repo.get(__MODULE__, config_id) do
      %__MODULE__{user_id: ^user_id} = conf ->
        {:ok, conf}

      %__MODULE__{} ->
        {:error,
         "Chart configuration with id #{config_id} is not owned by the user with id #{user_id}"}

      nil ->
        {:error, "Chart configuration with id #{config_id} does not exist."}
    end
  end

  defp get_chart_configurations(config_ids, opts) do
    preload = Keyword.get(opts, :preload, [:chart_events])

    query =
      from(
        conf in __MODULE__,
        where: conf.id in ^config_ids and conf.is_public == true,
        preload: ^preload,
        order_by: fragment("array_position(?, ?::int)", ^config_ids, conf.id)
      )

    {:ok, Repo.all(query)}
  end

  defp user_chart_configurations_query(user_id, querying_user_id, nil) do
    __MODULE__
    |> where([conf], conf.user_id == ^user_id)
    |> accessible_by_user_query(querying_user_id)
  end

  defp user_chart_configurations_query(user_id, querying_user_id, project_id) do
    filter_by_project_query(project_id)
    |> where([conf], conf.user_id == ^user_id)
    |> accessible_by_user_query(querying_user_id)
  end

  defp project_chart_configurations_query(project_id, querying_user_id) do
    filter_by_project_query(project_id)
    |> accessible_by_user_query(querying_user_id)
  end

  defp filter_by_project_query(project_id) when not is_nil(project_id) do
    __MODULE__
    |> where([conf], conf.project_id == ^project_id)
  end

  defp accessible_by_user_query(query, nil) do
    query
    |> where([conf], conf.is_public == true)
  end

  defp accessible_by_user_query(query, querying_user_id) do
    query
    |> where([conf], conf.is_public == true or conf.user_id == ^querying_user_id)
  end
end
