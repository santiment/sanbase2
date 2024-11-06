defmodule Sanbase.Metric.Registry do
  use Ecto.Schema

  import Ecto.Changeset
  import Sanbase.Metric.Registry.EventEmitter, only: [emit_event: 3]

  alias Sanbase.Repo
  alias __MODULE__.Validation
  alias Sanbase.TemplateEngine

  # Matches letters, digits, _, -, :, ., {, }, (, ), \, /  and space
  # Careful not to delete the space at the end
  @human_readable_name_regex ~r|^[a-zA-Z0-9_\.\-{}():/\\ ]+$|
  @aggregations ["sum", "last", "count", "avg", "max", "min", "first"]
  def aggregations(), do: @aggregations

  @type t :: %__MODULE__{
          id: integer(),
          metric: String.t(),
          human_readable_name: String.t(),
          aliases: [String.t()],
          internal_metric: String.t(),
          tables: [String.t()],
          default_aggregation: String.t(),
          min_interval: String.t(),
          access: String.t(),
          min_plan: map(),
          selectors: [String.t()],
          required_selectors: [String.t()],
          is_template: boolean(),
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
          docs: [String.t()],
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defmodule Selector do
    use Ecto.Schema
    import Ecto.Changeset

    embedded_schema do
      field(:type, :string)
    end

    def changeset(%__MODULE__{} = struct, attrs) do
      struct
      |> cast(attrs, [:type])
      |> validate_required([:type])
    end
  end

  defmodule Table do
    use Ecto.Schema
    import Ecto.Changeset

    embedded_schema do
      field(:name, :string)
    end

    def changeset(%__MODULE__{} = struct, attrs) do
      struct
      |> cast(attrs, [:name])
      |> validate_required([:name])
    end
  end

  defmodule Alias do
    use Ecto.Schema
    import Ecto.Changeset

    embedded_schema do
      field(:name, :string)
    end

    def changeset(%__MODULE__{} = struct, attrs) do
      struct
      |> cast(attrs, [:name])
      |> validate_required([:name])
    end
  end

  defmodule Doc do
    use Ecto.Schema
    import Ecto.Changeset

    embedded_schema do
      field(:link, :string)
    end

    def changeset(%__MODULE__{} = struct, attrs) do
      struct
      |> cast(attrs, [:link])
      |> validate_required([:link])
    end
  end

  @timestamps_opts [type: :utc_datetime]
  schema "metric_registry" do
    # How the metric is exposed to external users
    field(:metric, :string)
    field(:human_readable_name, :string)
    embeds_many(:aliases, Alias, on_replace: :delete)

    # What is the name of the metric in the DB and where to find it
    field(:internal_metric, :string)
    embeds_many(:tables, Table, on_replace: :delete)

    field(:default_aggregation, :string)
    field(:min_interval, :string)
    field(:access, :string)
    field(:min_plan, :map)
    embeds_many(:selectors, Selector, on_replace: :delete)
    embeds_many(:required_selectors, Selector, on_replace: :delete)

    # If the metric is a template metric, then the parameters need to be used
    # to define the full set of metrics
    field(:is_template, :boolean, default: false)
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
    embeds_many(:docs, Doc)

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
      :is_exposed,
      :is_hidden,
      :is_template,
      :is_timebound,
      :metric,
      :min_interval,
      :min_plan,
      :parameters
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
    |> validate_required([
      :access,
      :default_aggregation,
      :has_incomplete_data,
      :human_readable_name,
      :internal_metric,
      :metric,
      :min_interval
    ])
    |> validate_format(:metric, ~r/^[a-z0-9_{}:]+$/)
    |> validate_format(:internal_metric, ~r/^[a-z0-9_{}:]+$/)
    |> validate_format(:human_readable_name, @human_readable_name_regex)
    |> validate_length(:metric, min: 3, max: 100)
    |> validate_length(:internal_metric, min: 3, max: 100)
    |> validate_length(:human_readable_name, min: 3, max: 120)
    |> validate_inclusion(:default_aggregation, @aggregations)
    |> validate_inclusion(:data_type, ["timeseries", "histogram", "table"])
    |> validate_inclusion(:exposed_environments, ["all", "none", "stage", "prod"])
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

  def by_id(id) do
    case Sanbase.Repo.get_by(__MODULE__, id: id) do
      nil -> {:error, "No metric with id #{id} found in the registry"}
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
