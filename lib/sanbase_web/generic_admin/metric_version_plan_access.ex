defmodule SanbaseWeb.GenericAdmin.MetricVersionPlanAccess do
  @moduledoc """
  Admin CRUD for `Sanbase.Metric.VersionPlanAccess` - which plans may use a metric
  version. Removing a row takes the version away from that plan at once (while
  `METRIC_VERSION_ACCESS_ENFORCE` is on).
  """

  @behaviour SanbaseWeb.GenericAdmin

  import Ecto.Query, only: [from: 2]

  alias Sanbase.Metric.VersionAlias
  alias Sanbase.Metric.VersionPlanAccess

  @impl SanbaseWeb.GenericAdmin
  def schema_module(), do: VersionPlanAccess

  @impl SanbaseWeb.GenericAdmin
  def resource_name(), do: "metric_version_plan_access"

  @impl SanbaseWeb.GenericAdmin
  def singular_resource_name(), do: "metric_version_plan_access"

  @fields [:product, :plan, :billing_interval, :include_trial]

  def resource() do
    %{
      actions: [:new, :edit, :delete],
      preloads: [:version_alias],
      index_fields: [:id, :version_alias_id | @fields],
      new_fields: [:version_alias | @fields],
      edit_fields: [:version_alias | @fields],
      belongs_to_fields: %{
        version_alias: %{
          query: from(a in VersionAlias, order_by: [a.scope, a.version_num]),
          transform: fn rows -> Enum.map(rows, &{alias_label(&1), &1.id}) end,
          resource: "metric_version_aliases",
          search_fields: [:version_name, :version_num, :scope]
        }
      },
      fields_override: %{
        version_alias_id: %{value_modifier: &alias_link/1},
        product: %{type: :select, collection: VersionPlanAccess.products()},
        plan: %{type: :select, collection: VersionPlanAccess.plans()},
        billing_interval: %{type: :select, collection: VersionPlanAccess.billing_intervals()}
      }
    }
  end

  def alias_link(row) do
    SanbaseWeb.GenericAdmin.resource_link(
      "metric_version_aliases",
      row.version_alias_id,
      alias_label(row.version_alias)
    )
  end

  defp alias_label(%VersionAlias{} = row),
    do: "#{row.version_name} (#{row.version_num}, #{row.scope})"

  def after_filter(_record, _changeset, _changes), do: VersionAlias.clear_cache()

  def after_delete(_record), do: VersionAlias.clear_cache()
end
