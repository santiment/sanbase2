defmodule SanbaseWeb.GenericAdmin.Notification do
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
        :is_manual
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
