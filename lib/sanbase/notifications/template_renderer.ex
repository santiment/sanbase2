defmodule Sanbase.Notifications.TemplateRenderer do
  alias Sanbase.Notifications.{Notification, NotificationAction}

  def render_content(%Notification{
        notification_action: %NotificationAction{action_type: :create},
        template_params: %{"metrics_list" => metrics_list}
      }) do
    """
    In the latest update the following metrics have been added:
    #{format_metrics(metrics_list)}
    For more information, please visit #changelog
    """
    |> String.trim()
  end

  def render_content(%Notification{
        notification_action: %NotificationAction{action_type: :update} = _action,
        step: :before,
        template_params: %{
          "scheduled_at" => scheduled_at,
          "duration" => duration,
          "metrics_list" => metrics_list
        }
      }) do
    metrics_list = format_metrics(metrics_list)

    """
    In order to make our data more precise, we’re going to run a recalculation of the following metrics:
    #{metrics_list}
    This will be done on #{scheduled_at} and will take approximately #{duration}
    """
    |> String.trim()
  end

  def render_content(%Notification{
        notification_action: %NotificationAction{action_type: :update} = _action,
        template_params: %{"metrics_list" => metrics_list},
        step: :after
      }) do
    metrics_list = format_metrics(metrics_list)

    """
    Recalculation of the following metrics has been completed successfully:
    #{metrics_list}
    """
    |> String.trim()
  end

  def render_content(%Notification{
        notification_action: %NotificationAction{action_type: :delete} = _action,
        step: :before,
        template_params: %{"scheduled_at" => scheduled_at, "metrics_list" => metrics_list}
      }) do
    metrics_list = format_metrics(metrics_list)

    """
    Due to lack of usage, we made a decision to deprecate the following metrics:
    #{metrics_list}
    This is planned to take place on #{scheduled_at}. Please make sure that you adjust your data consumption accordingly. If you have strong objections, please contact us.
    """
    |> String.trim()
  end

  def render_content(%Notification{
        notification_action: %NotificationAction{action_type: :delete} = _action,
        step: :reminder,
        template_params: %{"scheduled_at" => scheduled_at, "metrics_list" => metrics_list}
      }) do
    metrics_list = format_metrics(metrics_list)

    """
    This is a reminder about the scheduled deprecation of the following metrics:
    #{metrics_list}
    It will happen on #{scheduled_at}. Please make sure to adjust accordingly.
    """
    |> String.trim()
  end

  def render_content(%Notification{
        notification_action: %NotificationAction{action_type: :delete} = _action,
        step: :after,
        template_params: %{"metrics_list" => metrics_list}
      }) do
    metrics_list = format_metrics(metrics_list)

    """
    Deprecation of the following metrics has been completed successfully:
    #{metrics_list}
    """
    |> String.trim()
  end

  def render_content(%Notification{
        notification_action: %NotificationAction{action_type: :alert} = _action,
        step: :detected,
        template_params: %{"metric_name" => metric_name, "asset_categories" => asset_categories}
      }) do
    """
    Metric delay alert: #{metric_name} is experiencing a delay due to technical issues. Affected assets: #{Enum.join(asset_categories, ", ")}
    """
    |> String.trim()
  end

  def render_content(%Notification{
        notification_action: %NotificationAction{action_type: :alert} = _action,
        step: :resolved,
        template_params: %{"metric_name" => metric_name}
      }) do
    """
    Metric delay resolved: #{metric_name} is back to normal
    """
    |> String.trim()
  end

  defp format_metrics(metrics_list) do
    Enum.join(metrics_list, ", ")
  end
end
