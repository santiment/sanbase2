defmodule SanbaseWeb.GenericAdmin.MetricVersionAlias do
  @moduledoc """
  Admin CRUD for `Sanbase.Metric.VersionAlias` at
  `/admin/generic?resource=metric_version_aliases`.

  `scope_value` is used only for metric scope; category scope uses the category
  select. Renaming or deleting an alias breaks API clients that send that name
  (numeric versions are unaffected), and other nodes see the change within about
  five minutes.
  """

  @behaviour SanbaseWeb.GenericAdmin

  require Logger

  alias Sanbase.Metric.VersionAlias

  def schema_module(), do: VersionAlias
  def resource_name(), do: "metric_version_aliases"
  def singular_resource_name(), do: "metric_version_alias"

  @fields [
    :scope_type,
    :scope_value,
    :category_id,
    :version_num,
    :version_name,
    :description,
    :priority
  ]

  def resource() do
    %{
      actions: [:new, :edit, :delete],
      preloads: [:category],
      index_fields: [:id | @fields] ++ [:updated_at],
      new_fields: @fields,
      edit_fields: @fields,
      fields_override: %{
        scope_type: %{type: :select, collection: VersionAlias.scope_types()},
        category_id: %{
          type: :select,
          collection: category_collection(),
          value_modifier: &category_name/1
        }
      }
    }
  end

  # Both hooks drop this node's cached rows so the next request already sees the
  # new effective mapping. Other nodes converge on cache expiry.
  def after_filter(_record, _changeset, _changes) do
    VersionAlias.clear_cache()
    :ok
  end

  def after_delete(_record) do
    VersionAlias.clear_cache()
    :ok
  end

  # `resource/0` runs on every admin request for every resource, so the list is
  # cached briefly, and a failing query degrades this form instead of every
  # admin page.
  defp category_collection() do
    Sanbase.Cache.get_or_store({{__MODULE__, :categories}, 60}, fn ->
      Enum.map(Sanbase.Metric.Category.list_categories(), &{&1.name, &1.id})
    end)
  rescue
    e ->
      Logger.error("Cannot list metric categories for the alias form: #{Exception.message(e)}")
      []
  end

  defp category_name(%VersionAlias{category: %{name: name}}), do: name
  defp category_name(%VersionAlias{category_id: category_id}), do: category_id
end
