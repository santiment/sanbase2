defmodule SanbaseWeb.GenericAdmin.Notification do
  use SanbaseWeb, :live_component

  def schema_module, do: Sanbase.Notifications.Notification

  def resource() do
    %{
      index_fields: [
        :id,
        :action,
        :step,
        :params,
        :channel,
        :status,
        :is_manual,
        :scheduled_at
      ],
      custom_index_actions: [
        %{
          name: "Manual Discord Notification",
          path: ~p"/admin2/notifications/manual/discord"
        },
        %{
          name: "Manual Email Notification",
          path: ~p"/admin2/notifications/manual/email"
        }
      ],
      fields_override: %{
        action: %{
          collection: Sanbase.Notifications.Notification.supported_actions(),
          type: :select
        },
        step: %{
          collection: Sanbase.Notifications.Notification.supported_steps(),
          type: :select
        },
        channel: %{
          collection: Sanbase.Notifications.Notification.supported_channels(),
          type: :select
        },
        params: %{
          value_modifier: fn ntf ->
            Jason.encode!(ntf.params)
          end
        },
        job_id: %{
          value_modifier: fn ntf ->
            case ntf.job_id do
              nil ->
                nil

              job_id ->
                PhoenixHTMLHelpers.Link.link(job_id,
                  to: "/admin2/generic/#{job_id}?resource=oban_jobs",
                  class: "text-blue-600 hover:text-blue-800"
                )
            end
          end
        },
        metric_registry_id: %{
          value_modifier: fn ntf ->
            case ntf.metric_registry_id do
              nil ->
                nil

              metric_registry_id ->
                PhoenixHTMLHelpers.Link.link(metric_registry_id,
                  to: "/admin2/metric_registry/show/#{metric_registry_id}",
                  class: "text-blue-600 hover:text-blue-800"
                )
            end
          end
        }
      }
    }
  end
end
