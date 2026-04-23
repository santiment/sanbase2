defmodule SanbaseWeb.GenericAdmin.SourceSlugMapping do
  @behaviour SanbaseWeb.GenericAdmin
  def schema_module, do: Sanbase.Project.SourceSlugMapping
  def resource_name, do: "source_slug_mappings"
  def singular_resource_name, do: "source_slug_mapping"

  def resource() do
    %{
      actions: [:new, :edit, :delete],
      preloads: [:project],
      new_fields: [:project, :source, :slug],
      edit_fields: [:project, :source, :slug],
      fields_override: %{
        project_id: %{
          value_modifier: &SanbaseWeb.GenericAdmin.Project.project_link/1
        },
        source: %{
          collection: ["cryptocompare", "coinmarketcap", "binance"],
          type: :select
        }
      },
      belongs_to_fields: %{
        project: SanbaseWeb.GenericAdmin.belongs_to_project()
      }
    }
  end
end
