defmodule SanbaseWeb.GenericAdmin.MetricVersionAlias do
  @moduledoc """
  Admin CRUD for `Sanbase.Metric.VersionAlias`. Renaming or deleting a name
  breaks API clients that send it; numeric versions are unaffected.
  """

  @behaviour SanbaseWeb.GenericAdmin

  alias Sanbase.Metric.VersionAlias

  @impl SanbaseWeb.GenericAdmin
  def schema_module(), do: VersionAlias

  @impl SanbaseWeb.GenericAdmin
  def resource_name(), do: "metric_version_aliases"

  @impl SanbaseWeb.GenericAdmin
  def singular_resource_name(), do: "metric_version_alias"

  @fields [:scope, :version_num, :version_name, :description]

  def resource() do
    %{
      actions: [:new, :edit, :delete],
      index_fields: [:id | @fields] ++ [:updated_at],
      new_fields: @fields,
      edit_fields: @fields,
      fields_override: %{
        scope: %{type: :select, collection: VersionAlias.list_scopes()}
      }
    }
  end

  def after_filter(_record, _changeset, _changes) do
    VersionAlias.clear_cache()
    :ok
  end

  def after_delete(_record) do
    VersionAlias.clear_cache()
    :ok
  end
end
