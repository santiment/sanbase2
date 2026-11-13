defmodule SanbaseWeb.GenericAdmin.ScheduleRescrapePrice do
  @behaviour SanbaseWeb.GenericAdmin

  alias Sanbase.ExternalServices.Coinmarketcap.ScheduleRescrapePrice

  def schema_module(), do: ScheduleRescrapePrice
  def resource_name(), do: "schedule_rescrape_prices"
  def singular_resource_name(), do: "schedule_rescrape_price"

  def resource() do
    %{
      actions: [:new, :edit, :delete],
      index_fields: [
        :id,
        :project_id,
        :from,
        :to,
        :priority,
        :status,
        :progress_datetime,
        :last_error,
        :started_at,
        :finished_at,
        :inserted_at
      ],
      new_fields: [:project, :from, :to, :priority],
      # Set the status to cancelled to stop a rescrape, or a failed rescrape
      # back to pending to resume it from where it stopped
      edit_fields: [:priority, :status],
      preloads: [:project],
      belongs_to_fields: %{
        project: SanbaseWeb.GenericAdmin.belongs_to_project()
      },
      fields_override: %{
        project_id: %{
          value_modifier: &SanbaseWeb.GenericAdmin.Project.project_link/1
        },
        priority: %{
          collection: ScheduleRescrapePrice.priorities() |> Enum.map(&to_string/1),
          type: :select
        },
        status: %{
          collection: ScheduleRescrapePrice.statuses() |> Enum.map(&to_string/1),
          type: :select
        }
      }
    }
  end
end
