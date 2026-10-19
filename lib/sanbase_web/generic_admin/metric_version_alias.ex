defmodule SanbaseWeb.GenericAdmin.MetricVersionAlias do
  @moduledoc """
  Admin CRUD for `Sanbase.Metric.VersionAlias`. Renaming or deleting a name
  breaks API clients that send it; numeric versions are unaffected. Deleting a row
  also deletes its plan access, so no plan can use the version any more.
  """

  @behaviour SanbaseWeb.GenericAdmin

  alias Sanbase.Metric.VersionAlias

  @impl SanbaseWeb.GenericAdmin
  def schema_module(), do: VersionAlias

  @impl SanbaseWeb.GenericAdmin
  def resource_name(), do: "metric_version_aliases"

  @impl SanbaseWeb.GenericAdmin
  def singular_resource_name(), do: "metric_version_alias"

  @fields [:scope, :version_num, :version_name, :exposed_in, :description]

  def resource() do
    %{
      actions: [:new, :edit, :delete],
      index_fields: [:id | @fields] ++ [:updated_at],
      new_fields: @fields,
      edit_fields: @fields,
      fields_override: %{
        scope: %{type: :select, collection: VersionAlias.scopes()},
        exposed_in: %{type: :select, collection: VersionAlias.exposures()}
      }
    }
  end

  def has_many(version_alias) do
    version_alias = Sanbase.Repo.preload(version_alias, :plan_access)

    [
      %{
        resource: "metric_version_plan_access",
        resource_name: "Plan access",
        rows: version_alias.plan_access,
        fields: [:product, :plan, :billing_interval, :include_trial],
        funcs: %{},
        create_link_kv: [linked_resource: :version_alias, linked_resource_id: version_alias.id]
      }
    ]
  end

  def after_filter(_record, _changeset, _changes), do: VersionAlias.clear_cache()

  def after_delete(_record), do: VersionAlias.clear_cache()
end
