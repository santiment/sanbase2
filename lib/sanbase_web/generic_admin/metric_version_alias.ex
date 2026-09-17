defmodule SanbaseWeb.GenericAdmin.MetricVersionAlias do
  @moduledoc """
  Admin CRUD for `Sanbase.Metric.VersionAlias` at
  `/admin/generic?resource=metric_version_aliases`.

  Renaming or deleting an alias breaks API clients that send that name (numeric
  versions are unaffected). Every node drops its cached rows on save.
  """

  @behaviour SanbaseWeb.GenericAdmin

  alias Sanbase.Metric.VersionAlias

  def schema_module(), do: VersionAlias
  def resource_name(), do: "metric_version_aliases"
  def singular_resource_name(), do: "metric_version_alias"

  @fields [:scope, :version_num, :version_name, :description]

  def resource() do
    %{
      actions: [:new, :edit, :delete],
      index_fields: [:id | @fields] ++ [:updated_at],
      new_fields: @fields,
      edit_fields: @fields,
      fields_override: %{
        scope: %{type: :select, collection: VersionAlias.scopes()}
      }
    }
  end

  # Both hooks drop the cached rows on every node, so the next request anywhere
  # already sees the new mapping.
  def after_filter(_record, _changeset, _changes) do
    VersionAlias.clear_cache()
    :ok
  end

  def after_delete(_record) do
    VersionAlias.clear_cache()
    :ok
  end
end
