defmodule Sanbase.Metric.Registry do
  use Ecto.Schema

  import Ecto.Changeset

  alias __MODULE__.Validation
  alias Sanbase.TemplateEngine

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

  def changeset(%__MODULE__{} = metric_description, attrs) do
    metric_description
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
    |> validate_inclusion(:aggregation, ["sum", "last", "count", "avg", "max", "min", "first"])
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

  def all(), do: Sanbase.Repo.all(__MODULE__)

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
