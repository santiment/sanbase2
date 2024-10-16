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
      :hard_deprecate_after
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
      nil
    end)
  end
end
