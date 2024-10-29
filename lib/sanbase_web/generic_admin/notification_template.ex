defmodule SanbaseWeb.GenericAdmin.NotificationTemplate do
  def schema_module, do: Sanbase.Notifications.NotificationTemplate

  def resource() do
    %{
      actions: [:new, :edit, :delete],
      new_fields: [:channel, :action_type, :step, :template],
      edit_fields: [:channel, :action_type, :step, :template],
      fields_override: %{
        template: %{
          type: :text
        },
        channel: %{
          type: :select,
          collection: ["email", "telegram", "discord", "all"]
        },
        action_type: %{
          type: :select,
          collection: NotificationActionTypeEnum.__enum_map__() |> Enum.map(&to_string(&1))
        },
        step: %{
          type: :select,
          collection: NotificationStepEnum.__enum_map__() |> Enum.map(&to_string(&1))
        }
      }
    }
  end
end
