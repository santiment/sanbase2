defmodule Sanbase.Metric.Registry do
  use Ecto.Schema

  import Ecto.Changeset

  alias __MODULE__.Validation

  schema "metric_registry" do
    # How the metric is exposed to external users
    field(:metric, :string)
    field(:human_readable_name, :string)
    field(:aliases, {:array, :string}, default: [])

    # What is the name of the metric in the DB and where to find it
    field(:internal_metric, :string)
    field(:table, :string)

    field(:aggregation, :string)
    field(:min_interval, :string)

    # If the metric is a template metric, then the parameters need to be used
    # to define the full set of metrics
    field(:is_template_metric, :boolean, default: false)
    field(:parameters, :map, default: %{})

    field(:is_deprecated, :boolean, default: false)
    field(:hard_deprecate_after, :utc_datetime, default: nil)

    field(:data_type, :string)
    field(:docs_links, {:array, :string}, default: [])

    timestamps()
  end

  def changeset(%__MODULE__{} = metric_description, attrs) do
    metric_description
    |> cast(attrs, [
      :metric,
      :internal_metric,
      :human_readable_name,
      :aliases,
      :table,
      :is_template_metric,
      :parameters,
      :aggregation,
      :min_interval,
      :is_deprecated,
      :hard_deprecate_after,
      :data_type,
      :docs_links
    ])
    |> validate_required([
      :metric,
      :internal_metric,
      :human_readable_name,
      :table,
      :aggregation,
      :min_interval
    ])
    |> validate_change(:aggregation, &Validation.validate_aggregation/2)
    |> validate_change(:min_interval, &Validation.validate_min_interval/2)
    |> validate_change(:data_type, &Validation.validate_data_type/2)
  end

  def populate() do
    Sanbase.Clickhouse.MetricAdapter.FileHandler.metrics_json()
    |> Enum.map(fn map ->
      {:ok, captures} = Sanbase.TemplateEngine.Captures.extract_captures(map["metric"])
      is_template_metric = captures != []

      %__MODULE__{}
      |> changeset(%{
        metric: map["metric"],
        internal_metric: map["internal_metric"],
        human_readable_name: map["human_readable_name"],
        aliases: map["aliases"],
        table: map["table"],
        aggregation: map["aggregation"],
        min_interval: map["min_interval"],
        is_template_metric: is_template_metric,
        parameters: Map.get(map, "parameters", %{}),
        is_deprecated: Map.get(map, "is_deprecated", false),
        hard_deprecate_after: map["hard_deprecate_after"],
        has_incomplete_data: Map.get(map, "has__incomplete_data", false),
        data_type: map["data_type"],
        docs_links: Map.get(map, "docs_links", [])
      })
    end)
  end
end
