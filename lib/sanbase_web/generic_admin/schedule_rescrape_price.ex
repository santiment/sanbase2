defmodule SanbaseWeb.GenericAdmin.ScheduleRescrapePrice do
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
        project: SanbaseWeb.GenericAdmin.belongs_to_project()
      },
      fields_override: %{
        project_id: %{
          value_modifier: &SanbaseWeb.GenericAdmin.Project.project_link/1
        }
      }
    }
  end
end
