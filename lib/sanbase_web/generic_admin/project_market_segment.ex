defmodule SanbaseWeb.GenericAdmin.ProjectMarketSegments do
  @behaviour SanbaseWeb.GenericAdmin
  import Ecto.Query
  def schema_module, do: Sanbase.Project.ProjectMarketSegment
  def resource_name, do: "project_market_segments"
  def singular_resource_name, do: "project_market_segment"

  def resource() do
    %{
      actions: [:new, :edit, :delete],
      preloads: [:project, :market_segment],
      new_fields: [:project, :market_segment],
      edit_fields: [:project, :market_segment],
      belongs_to_fields: %{
        market_segment: %{
          query: from(ms in Sanbase.Model.MarketSegment, order_by: ms.id),
          transform: fn rows -> Enum.map(rows, &{&1.name, &1.id}) end,
          resource: "market_segments",
          search_fields: [:name]
        },
        project: SanbaseWeb.GenericAdmin.belongs_to_project()
      },
      fields_override: %{
        project_id: %{
          value_modifier: &SanbaseWeb.GenericAdmin.Project.project_link/1
        },
        market_segment_id: %{
          value_modifier: &__MODULE__.market_segment_link/1
        }
      }
    }
  end

  def market_segment_link(row) do
    SanbaseWeb.GenericAdmin.resource_link(
      "market_segments",
      row.market_segment_id,
      row.market_segment.name
    )
  end
end
