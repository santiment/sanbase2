defmodule SanbaseWeb.GenericAdmin.MetricVersionAlias do
  @moduledoc """
  Admin CRUD for `Sanbase.Metric.VersionAlias` at
  `/admin/generic?resource=metric_version_aliases`.

  Renaming or deleting an alias breaks API clients that send that name (numeric
  versions are unaffected), and other nodes see the change within about five
  minutes.
  """

  @behaviour SanbaseWeb.GenericAdmin

  alias Sanbase.Metric.VersionAlias

  def schema_module(), do: VersionAlias
  def resource_name(), do: "metric_version_aliases"
  def singular_resource_name(), do: "metric_version_alias"

  @fields [:version_num, :version_name, :description]

  def resource() do
    %{
      actions: [:new, :edit, :delete],
      index_fields: [:id | @fields] ++ [:updated_at],
      new_fields: @fields,
      edit_fields: @fields
    }
  end

  # Both hooks drop this node's cached rows so the next request already sees the
  # new mapping. Other nodes converge on cache expiry.
  def after_filter(_record, _changeset, _changes) do
    VersionAlias.clear_cache()
    :ok
  end

  def after_delete(_record) do
    VersionAlias.clear_cache()
    :ok
  end
end
