defmodule Sanbase.Metric.Registry do
  use Ecto.Schema

  schema "metric_registry" do
    #
    field(:name, :string)
    field(:human_readable_name, :string)

    # What is the name of the metric in the DB and where to find it
    field(:internal_metric, :string)
    field(:table, :string)

    # If the metric is a template metric, then the parameters need to be used
    # to define the full set of metrics
    field(:is_template_metric, :boolean, default: false)
    field(:parameters, :map, default: %{})

    timestamps()
  end
end
