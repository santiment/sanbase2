defmodule Sanbase.Metric.Registry do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset
  import Sanbase.Metric.Registry.EventEmitter, only: [emit_event: 3]

  alias __MODULE__.Validation
  alias __MODULE__.ChangeSuggestion
  alias __MODULE__.Doc
  alias __MODULE__.Alias
  alias __MODULE__.Selector
  alias __MODULE__.Table

  alias Sanbase.Repo
  alias Sanbase.TemplateEngine

  # Matches letters, digits, _, -, :, ., {, }, (, ), \, /  and space
  # Careful not to delete the space at the end
  @human_readable_name_regex ~r|^[a-zA-Z0-9_\.\-{}():/\\ ]+$|
  @aggregations ["sum", "last", "count", "avg", "max", "min", "first"]
  def aggregations(), do: @aggregations
  @metric_regex ~r/^[a-z0-9_{}:]+$/
  def metric_regex(), do: @metric_regex
  @allowed_statuses ["alpha", "beta", "released"]
  def allowed_statuses(), do: @allowed_statuses

  @type t :: %__MODULE__{
          id: integer(),
          metric: String.t(),
          human_readable_name: String.t(),
          aliases: [%Alias{}],
          internal_metric: String.t(),
          tables: [%Table{}],
          default_aggregation: String.t(),
          min_interval: String.t(),
          access: String.t(),
          sanbase_min_plan: String.t(),
          sanapi_min_plan: String.t(),
          selectors: [%Selector{}],
          required_selectors: [%Selector{}],
          is_template: boolean(),
          parameters: [map()],
          fixed_parameters: map(),
          is_timebound: boolean(),
          has_incomplete_data: boolean(),
          exposed_environments: String.t(),
          is_hidden: boolean(),
          is_deprecated: boolean(),
          hard_deprecate_after: DateTime.t(),
          deprecation_note: String.t(),
          data_type: String.t(),
          docs: [%Doc{}],
          status: String.t(),
          is_verified: boolean(),
          sync_status: String.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  # The struct is encoded to JSON when it is being synced to prod
  # The fields specified in the :except are the ones that should
  # not be synced.
  @derive {Jason.Encoder,
           except: [
             :__struct__,
             :__meta__,
             :id,
             :inserted_at,
             :updated_at,
             :sync_status,
             :change_suggestions
           ]}

  @timestamps_opts [type: :utc_datetime]
  schema "metric_registry" do
    # How the metric is exposed to external users
    field(:metric, :string)
    field(:human_readable_name, :string)
    embeds_many(:aliases, Alias, on_replace: :delete)

    # What is the name of the metric in the DB and where to find it
    field(:internal_metric, :string)

    field(:default_aggregation, :string)
    field(:min_interval, :string)
    field(:access, :string)
    field(:sanbase_min_plan, :string)
    field(:sanapi_min_plan, :string)

    # If the metric is a template metric, then the parameters need to be used
    # to define the full set of metrics
    field(:is_template, :boolean, default: false)
    field(:parameters, {:array, :map}, default: [])
    field(:fixed_parameters, :map, default: %{})

    field(:is_timebound, :boolean, default: false)
    field(:has_incomplete_data, :boolean, default: false)

    field(:exposed_environments, :string, default: "all")

    field(:is_hidden, :boolean, default: false)
    field(:is_deprecated, :boolean, default: false)
    field(:hard_deprecate_after, :utc_datetime, default: nil)
    field(:deprecation_note, :string, default: nil)
    field(:data_type, :string, default: "timeseries")

    field(:status, :string, default: "released")
    # Sync-related fields
    field(:is_verified, :boolean)
    field(:sync_status, :string)

    embeds_many(:tables, Table, on_replace: :delete)
    embeds_many(:selectors, Selector, on_replace: :delete)
    embeds_many(:required_selectors, Selector, on_replace: :delete)
    embeds_many(:docs, Doc, on_replace: :delete)

    has_many(:change_suggestions, ChangeSuggestion,
      foreign_key: :metric_registry_id,
      on_delete: :delete_all
    )

    timestamps()
  end

  def changeset(%__MODULE__{} = metric_registry, attrs) do
    metric_registry
    |> cast(attrs, [
      :access,
      :default_aggregation,
      :data_type,
      :deprecation_note,
      :exposed_environments,
      :fixed_parameters,
      :hard_deprecate_after,
      :has_incomplete_data,
      :human_readable_name,
      :internal_metric,
      :is_deprecated,
      :is_hidden,
      :is_template,
      :is_timebound,
      :is_verified,
      :metric,
      :min_interval,
      :sanbase_min_plan,
      :sanapi_min_plan,
      :parameters,
      :status,
      :sync_status
    ])
    |> cast_embed(:selectors,
      required: false,
      with: &Selector.changeset/2,
      sort_param: :selectors_sort,
      drop_param: :selectors_drop
    )
    |> cast_embed(:required_selectors,
      required: false,
      with: &Selector.changeset/2,
      sort_param: :required_selectors_sort,
      drop_param: :required_selectors_drop
    )
    |> cast_embed(:tables,
      required: false,
      with: &Table.changeset/2,
      sort_param: :tables_sort,
      drop_param: :tables_drop
    )
    |> cast_embed(:aliases,
      required: false,
      with: &Alias.changeset/2,
      sort_param: :aliases_sort,
      drop_param: :aliases_drop
    )
    |> cast_embed(:docs,
      required: false,
      with: &Doc.changeset/2,
      sort_param: :docs_sort,
      drop_param: :docs_drop
    )
    |> validate_required([
      :access,
      :default_aggregation,
      :has_incomplete_data,
      :human_readable_name,
      :internal_metric,
      :metric,
      :min_interval
    ])
    |> validate_format(:metric, @metric_regex)
    |> validate_format(:internal_metric, @metric_regex)
    |> validate_format(:human_readable_name, @human_readable_name_regex)
    |> validate_length(:metric, min: 3, max: 100)
    |> validate_length(:internal_metric, min: 3, max: 100)
    |> validate_length(:human_readable_name, min: 3, max: 120)
    |> validate_inclusion(:default_aggregation, @aggregations)
    |> validate_inclusion(:data_type, ["timeseries", "histogram", "table"])
    |> validate_inclusion(:exposed_environments, ["all", "none", "stage", "prod"])
    |> validate_inclusion(:access, ["free", "restricted"])
    |> validate_change(:min_interval, &Validation.validate_min_interval/2)
    |> validate_change(:sync_status, &Validation.validate_sync_status/2)
    |> validate_inclusion(:sanbase_min_plan, ["free", "pro", "max"])
    |> validate_inclusion(:sanapi_min_plan, ["free", "pro", "max"])
    |> validate_inclusion(:status, @allowed_statuses)
    |> Validation.validate_template_fields()
    |> unique_constraint([:metric, :data_type, :fixed_parameters],
      name: :metric_registry_composite_unique_index
    )
  end

  def create(attrs, opts \\ []) do
    attrs = Map.merge(attrs, %{sync_status: "not_synced", is_verified: false})

    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
    |> maybe_emit_event(:create_metric_registry, opts)
  end

  def update(%__MODULE__{} = metric_registry, attrs, opts \\ []) do
    metric_registry
    |> changeset(attrs)
    |> then(fn changeset ->
      if changeset.changes != %{},
        do: changeset |> put_change(:sync_status, "not_synced"),
        else: changeset
    end)
    |> then(fn changeset ->
      if changeset.changes != %{} and attrs[:is_verified] != true,
        do: changeset |> put_change(:is_verified, false),
        else: changeset
    end)
    |> Repo.update()
    |> maybe_emit_event(:update_metric_registry, opts)
  end

  def delete(%__MODULE__{} = metric_registry, opts \\ []) do
    metric_registry
    |> Repo.delete()
    |> maybe_emit_event(:delete_metric_registry, opts)
  end

  def by_id(id) do
    case Sanbase.Repo.get_by(__MODULE__, id: id) do
      nil -> {:error, "No metric with id #{id} found in the registry"}
      %__MODULE__{} = struct -> {:ok, struct}
    end
  end

  def by_name(metric, data_type \\ "timeseries", fixed_parameters \\ %{}) do
    query =
      from(mr in __MODULE__,
        where:
          mr.metric == ^metric and mr.data_type == ^data_type and
            mr.fixed_parameters == ^fixed_parameters
      )

    case Sanbase.Repo.one(query) do
      %__MODULE__{} = struct ->
        {:ok, struct}

      nil ->
        {:error,
         """
         No metric with name #{metric}, data type #{data_type} and \
         fixed parameters #{inspect(fixed_parameters)} found in the registry
         """}
    end
  end

  @doc ~s"""
  Invoke all the necessary refresh functions to ensure the data stored
  in persistent_term is refreshed.
  """
  @spec refresh_stored_terms() :: :ok
  def refresh_stored_terms() do
    # Do not change the order of these calls
    # It is important as some of the modules later refreshed later
    # depend on the modules refreshed earlier
    true = Sanbase.Clickhouse.MetricAdapter.Registry.refresh_stored_terms()
    true = Sanbase.Metric.Helper.refresh_stored_terms()
    true = Sanbase.Billing.Plan.StandardAccessChecker.refresh_stored_terms()

    :ok
  end

  @doc ~s"""
  Get all the metric registry records. The records are not immedietaly
  ready for usage, as some of the records might be template metrics which
  need to be resolved, or aliases need to be applied.
  """
  @spec all() :: [t()]
  def all() do
    query = from(m in __MODULE__, order_by: [asc: m.id])

    Sanbase.Repo.all(query)
  end

  def by_ids(ids) do
    query = from(m in __MODULE__, where: m.id in ^ids)

    Sanbase.Repo.all(query)
  end

  @doc ~s"""
  Resolve all the metric registry records.
  This operation will increase the number of metrics by producing many metrics
  from template records and aliases.
  """
  @spec resolve([t()]) :: [t()]
  def resolve(list) when is_list(list) do
    Enum.flat_map(list, &resolve/1)
  end

  def resolve(%__MODULE__{} = registry) do
    registry
    |> resolve_aliases()
    |> Enum.flat_map(&apply_template_parameters/1)
  end

  # Private

  defp maybe_emit_event(result, event_type, opts)
       when is_tuple(result) and
              event_type in [
                :create_metric_registry,
                :update_metric_registry,
                :delete_metric_registry
              ] do
    if Keyword.get(opts, :emit_event, true) do
      emit_event(result, event_type, %{})
    else
      result
    end
  end

  defp resolve_aliases(%__MODULE__{} = registry) do
    aliases =
      registry.aliases
      |> Enum.map(& &1.name)
      |> Enum.map(fn metric_alias ->
        %{registry | metric: metric_alias}
      end)

    [registry] ++ aliases
  end

  defp apply_template_parameters(%__MODULE__{} = registry)
       when registry.is_template == true do
    %{
      metric: metric,
      internal_metric: internal_metric,
      human_readable_name: human_readable_name,
      parameters: parameters_list
    } = registry

    for parameters <- parameters_list do
      %{
        registry
        | metric: TemplateEngine.run!(metric, params: parameters),
          internal_metric: TemplateEngine.run!(internal_metric, params: parameters),
          human_readable_name: TemplateEngine.run!(human_readable_name, params: parameters)
      }
    end
  end

  defp apply_template_parameters(registry) when registry.is_template == false,
    do: [registry]
end
