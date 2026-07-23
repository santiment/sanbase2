defmodule Sanbase.Metric.MetricReference do
  @moduledoc """
  Shared changeset validation for mapping tables that reference a metric either
  by `metric_registry_id` (registry-backed metrics) or by a `module` + `metric`
  pair (code-defined metrics). Exactly one of the two forms must be set.

  Used by `Sanbase.Metric.Category.MetricCategoryMapping` and
  `Sanbase.Metric.Tag.MetricTagMapping`.
  """

  import Ecto.Changeset

  @spec validate_metric_reference(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate_metric_reference(changeset) do
    metric_registry_id = get_field(changeset, :metric_registry_id)
    module = get_field(changeset, :module)
    metric = get_field(changeset, :metric)

    if valid_metric_reference?(metric_registry_id, module, metric) do
      changeset
    else
      add_validation_error(changeset, metric_registry_id, module, metric)
    end
  end

  defp valid_metric_reference?(metric_registry_id, module, metric) do
    # Valid: metric_registry_id is set, module and metric are nil
    # Valid: metric_registry_id is nil, both module and metric are set
    is_metric_registry? = not is_nil(metric_registry_id) and is_nil(module) and is_nil(metric)
    is_module_metric? = is_nil(metric_registry_id) and not is_nil(module) and not is_nil(metric)

    is_metric_registry? or is_module_metric?
  end

  defp add_validation_error(changeset, metric_registry_id, module, metric) do
    cond do
      not is_nil(metric_registry_id) and (not is_nil(module) or not is_nil(metric)) ->
        add_error(changeset, :metric_registry_id, "cannot be set when module/metric are also set")

      not is_nil(module) and is_nil(metric) ->
        add_error(changeset, :metric, "must be set when module is set")

      is_nil(module) and not is_nil(metric) ->
        add_error(changeset, :module, "must be set when metric is set")

      true ->
        add_error(
          changeset,
          :base,
          "either metric_registry_id or both module and metric must be set"
        )
    end
  end
end
