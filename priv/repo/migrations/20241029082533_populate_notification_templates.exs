defmodule Sanbase.Repo.Migrations.PopulateNotificationTemplates do
  use Ecto.Migration
  alias Sanbase.Notifications.NotificationTemplate
  alias Sanbase.Repo

  import Ecto.Query

  def up do
    setup()

    templates = [
      %{
        channel: "all",
        action_type: "create",
        step: nil,
        template: """
        In the latest update the following metrics have been added:
        {{metrics_list}}
        For more information, please visit #changelog
        """
      },
      %{
        channel: "all",
        action_type: "update",
        step: "before",
        template: """
        In order to make our data more precise, we're going to run a recalculation of the following metrics:
        {{metrics_list}}
        This will be done on {{scheduled_at}} and will take approximately {{duration}}
        """
      },
      %{
        channel: "all",
        action_type: "update",
        step: "after",
        template: """
        Recalculation of the following metrics has been completed successfully:
        {{metrics_list}}
        """
      },
      %{
        channel: "all",
        action_type: "delete",
        step: "before",
        template: """
        Due to lack of usage, we made a decision to deprecate the following metrics:
        {{metrics_list}}
        This is planned to take place on {{scheduled_at}}. Please make sure that you adjust your data consumption accordingly. If you have strong objections, please contact us.
        """
      },
      %{
        channel: "all",
        action_type: "delete",
        step: "reminder",
        template: """
        This is a reminder about the scheduled deprecation of the following metrics:
        {{metrics_list}}
        It will happen on {{scheduled_at}}. Please make sure to adjust accordingly.
        """
      },
      %{
        channel: "all",
        action_type: "delete",
        step: "after",
        template: """
        Deprecation of the following metrics has been completed successfully:
        {{metrics_list}}
        """
      },
      %{
        channel: "all",
        action_type: "alert",
        step: "detected",
        template: """
        Metric delay alert: {{metric_name}} is experiencing a delay due to technical issues. Affected assets: {{asset_categories}}
        """
      },
      %{
        channel: "all",
        action_type: "alert",
        step: "resolved",
        template: """
        Metric delay resolved: {{metric_name}} is back to normal
        """
      }
    ]

    templates
    |> Enum.each(fn template_attrs ->
      %NotificationTemplate{}
      |> NotificationTemplate.changeset(template_attrs)
      |> Repo.insert!()
    end)
  end

  def down do
    setup()

    from(t in NotificationTemplate,
      where:
        t.channel == "all" and
          t.action_type in ["create", "update", "delete", "alert"]
    )
    |> Repo.delete_all()
  end

  defp setup do
    Application.ensure_all_started(:tzdata)
  end
end
