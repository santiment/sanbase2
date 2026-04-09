defmodule SanbaseWeb.GenericAdmin.Version do
  def schema_module, do: Sanbase.Version
  def resource_name, do: "versions"
  def singular_resource_name, do: "version"

  def resource() do
    %{
      actions: [:show],
      preloads: [:user],
      index_fields: [
        :id,
        :entity_id,
        :entity_schema,
        :action,
        :recorded_at,
        :rollback
      ],
      fields_override: %{
        patch: %{
          value_modifier: &Sanbase.ExAudit.Patch.format_patch/1
        }
      }
    }
  end
end
