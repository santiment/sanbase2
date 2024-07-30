defmodule SanbaseWeb.GenericAdmin.ScheduleRescrapePrice do
  import Ecto.Query
  def schema_module, do: Sanbase.ExternalServices.Coinmarketcap.ScheduleRescrapePrice

  def resource() do
    %{
      actions: [:new, :edit, :delete],
      index_fields: [
        :id,
        :project_id,
        :from,
        :to,
        :in_progress,
        :finished,
        :original_last_updated,
        :inserted_at,
        :updated_at
      ],
      new_fields: [:project, :from, :to],
      edit_fields: [:project, :from, :to],
      preloads: [:project],
      belongs_to_fields: %{
        project: %{
          query: from(p in Sanbase.Project, order_by: p.id),
          transform: fn rows -> Enum.map(rows, &{&1.name, &1.id}) end,
          resource: "projects",
          search_fields: [:name, :slug, :ticker]
        }
      },
      fields_override: %{
        project_id: %{
          value_modifier: &SanbaseWeb.GenericAdmin.Project.project_link/1
        }
      }
    }
  end
end
