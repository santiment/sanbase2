defmodule Sanbase.Metric.Registry do
  use Ecto.Schema

  import Ecto.Changeset
  import Sanbase.Metric.Registry.EventEmitter, only: [emit_event: 3]

  alias Sanbase.Repo
  alias __MODULE__.Validation
  alias Sanbase.TemplateEngine

  @aggregations ["sum", "last", "count", "avg", "max", "min", "first"]
  def aggregations(), do: @aggregations

  @type t :: %__MODULE__{
          id: integer(),
          metric: String.t(),
          human_readable_name: String.t(),
          aliases: [String.t()],
          internal_metric: String.t(),
          table: [String.t()],
          aggregation: String.t(),
          min_interval: String.t(),
          access: String.t(),
          min_plan: map(),
          selectors: [String.t()],
          required_selectors: [String.t()],
          is_template_metric: boolean(),
          parameters: [map()],
          fixed_parameters: map(),
          is_timebound: boolean(),
          has_incomplete_data: boolean(),
          is_exposed: boolean(),
          exposed_environments: String.t(),
          is_hidden: boolean(),
          is_deprecated: boolean(),
          hard_deprecate_after: DateTime.t(),
          deprecation_note: String.t(),
          data_type: String.t(),
          docs_links: [String.t()],
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @timestamps_opts [type: :utc_datetime]
  schema "metric_registry" do
    # How the metric is exposed to external users
    field(:metric, :string)
    field(:human_readable_name, :string)
    field(:aliases, {:array, :string}, default: [])

    # What is the name of the metric in the DB and where to find it
    field(:internal_metric, :string)
    field(:table, {:array, :string})

    field(:aggregation, :string)
    field(:min_interval, :string)
    field(:access, :string)
    field(:min_plan, :map)
    field(:selectors, {:array, :string})
    field(:required_selectors, {:array, :string})

    # If the metric is a template metric, then the parameters need to be used
    # to define the full set of metrics
    field(:is_template_metric, :boolean, default: false)
    field(:parameters, {:array, :map}, default: [])
    field(:fixed_parameters, :map, default: %{})

    field(:is_timebound, :boolean, default: false)
    field(:has_incomplete_data, :boolean, default: false)

    field(:is_exposed, :boolean, default: true)
    field(:exposed_environments, :string, default: "all")

    field(:is_hidden, :boolean, default: false)
    field(:is_deprecated, :boolean, default: false)
    field(:hard_deprecate_after, :utc_datetime, default: nil)
    field(:deprecation_note, :string, default: nil)

    field(:data_type, :string, default: "timeseries")
    field(:docs_links, {:array, :string}, default: [])

    timestamps()
  end

  def changeset(%__MODULE__{} = nmetric_registry, attrs) do
    nmetric_registry
    |> cast(attrs, [
      :access,
      :aggregation,
      :aliases,
      :data_type,
      :deprecation_note,
      :docs_links,
      :exposed_environments,
      :fixed_parameters,
      :hard_deprecate_after,
      :has_incomplete_data,
      :human_readable_name,
      :internal_metric,
      :is_deprecated,
      :is_exposed,
      :is_hidden,
      :is_template_metric,
      :is_timebound,
      :metric,
      :min_interval,
      :min_plan,
      :parameters,
      :required_selectors,
      :selectors,
      :table
    ])
    |> validate_required([
      :access,
      :aggregation,
      :has_incomplete_data,
      :human_readable_name,
      :internal_metric,
      :metric,
      :min_interval,
      :table
    ])
    |> validate_inclusion(:aggregation, @aggregations)
    |> validate_inclusion(:data_type, ["timeseries", "histogram", "table"])
    |> validate_inclusion(:exposed_environments, ["all", "stage", "prod"])
    |> validate_inclusion(:access, ["free", "restricted"])
    |> validate_change(:min_interval, &Validation.validate_min_interval/2)
    |> validate_change(:min_plan, &Validation.validate_min_plan/2)
    |> Validation.validate_template_fields()
    |> unique_constraint([:metric, :data_type, :fixed_parameters],
      name: :metric_registry_composite_unique_index
    )
  end

  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
    |> emit_event(:create_metric_registry, %{})
  end

  def update(%__MODULE__{} = metric_registry, attrs) do
    metric_registry
    |> changeset(attrs)
    |> Repo.update()
    |> emit_event(:update_metric_registry, %{})
  end

  def delete(%__MODULE__{} = metric_registry) do
    metric_registry
    |> Repo.delete()
    |> emit_event(:delete_metric_registry, %{})
  end

  def by_metric(metric) do
    case Sanbase.Repo.get_by(__MODULE__, metric: metric) do
      nil -> {:error, "No metric with name #{metric} found in the registry"}
      %__MODULE__{} = struct -> {:ok, struct}
    end
  end

  @doc ~s"""
  Get all the metric registry records. The records are not immedietaly
  ready for usage, as some of the records might be template metrics which
  need to be resolved, or aliases need to be applied.
  """
  @spec all() :: [t()]
  def all(), do: Sanbase.Repo.all(__MODULE__)

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

  defp resolve_aliases(%__MODULE__{} = registry) do
    [registry] ++
      Enum.map(registry.aliases, fn metric_alias ->
        %{registry | metric: metric_alias}
      end)
  end

  defp apply_template_parameters(%__MODULE__{} = registry)
       when registry.is_template_metric == true do
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

  defp apply_template_parameters(registry) when registry.is_template_metric == false,
    do: [registry]
end
