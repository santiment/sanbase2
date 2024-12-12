defmodule Sanbase.Notifications.Workers.ProcessNotification do
  use Oban.Worker, queue: :notifications_queue

  alias Sanbase.Notifications.{Notification, TemplateRenderer}
  alias Sanbase.Utils.Config

  @subject "Sanbase Metric Updates"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"is_manual" => true, "channel" => "discord"} = args}) do
    params = args["params"]
    notification_id = args["notification_id"]
    notification = Notification.by_id(notification_id)

    case Sanbase.Notifications.DiscordClient.client().send_message(
           discord_channel_webhook_map()[params["discord_channel"]] || discord_webhook(),
           params["content"],
           []
         ) do
      :ok -> mark_processed(notification)
      error -> error
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"is_manual" => true, "channel" => "email"} = args}) do
    params = args["params"]
    notification_id = args["notification_id"]
    notification = Notification.by_id(notification_id)

    case Sanbase.Email.MailjetApi.client().send_to_list(
           metric_updates_list(),
           params["subject"],
           params["content"],
           []
         ) do
      :ok -> mark_processed(notification)
      error -> error
    end
  end

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

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "change_status"} = args}) do
    notification_id = args["notification_id"]
    new_status = args["new_status"]

    notification = Notification.by_id(notification_id)
    Notification.update(notification, %{status: new_status})
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

  defp discord_channel_webhook_map do
    %{
      "metric_updates" => discord_webhook()
    }
  end
end
