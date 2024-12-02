defmodule Sanbase.Notifications.Workers.ProcessNotification do
  use Oban.Worker, queue: :email_notifications_queue

  alias Sanbase.Notifications.{Notification, TemplateRenderer}
  alias Sanbase.Utils.Config

  @subject "Sanbase Metric Updates"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"channel" => "discord"} = args}) do
    template_id = args["template_id"]
    params = args["params"]
    notification_id = args["notification_id"]

    content = TemplateRenderer.render(template_id, params)

    notification = Notification.by_id(notification_id)

    case Sanbase.Notifications.DiscordClient.client().send_message(discord_webhook(), content, []) do
      :ok -> mark_processed(notification)
      error -> error
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"channel" => "email"} = args}) do
    content =
      TemplateRenderer.render_content(%{
        action: args["action"],
        params: args["params"],
        step: args["step"],
        channel: "email"
      })

    case Sanbase.Email.MailjetApi.client().send_to_list(
           metric_updates_list(),
           @subject,
           content,
           []
         ) do
      :ok ->
        args["notification_ids"]
        |> Enum.map(&Notification.by_id/1)
        |> Enum.each(&mark_processed(&1))

      error ->
        error
    end
  end

  # For other channels (like email), we'll implement batching later
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"channel" => _other_channel}}) do
    :ok
  end

  defp discord_webhook do
    Config.module_get(Sanbase.Notifications, :discord_webhook)
  end

  defp metric_updates_list do
    Config.module_get(Sanbase.Notifications, :mailjet_metric_updates_list)
    |> String.to_atom()
  end

  defp mark_processed(notification) do
    Notification.update(notification, %{status: "completed"})
  end
end
