defmodule Sanbase.Notifications.Handler do
  alias Sanbase.{Repo, Notifications.Notification}
  alias Sanbase.Notifications.DiscordClient
  alias Sanbase.Notifications.TemplateRenderer
  alias Sanbase.Utils.Config

  @oban_conf_name :oban_web

  @default_channels %{
    "metric_created" => ["discord", "email"],
    "metric_updated" => ["discord", "email"],
    "metric_deleted" => ["discord", "email"],
    "alert" => ["discord"]
  }

  def handle_notification(%{action: "alert", params: params, step: step}) do
    {:ok, notification} = create_notification("alert", params, step)

    send_discord_notification(notification, "alert", params, step)

    {:ok, notification}
  end

  def handle_notification(%{action: "metric_created" = action, params: params}) do
    {:ok, notification} = create_notification(action, params, "all")

    send_discord_notification(notification, action, params, "all")

    {:ok, notification}
  end

  def handle_notification(%{action: "metric_deleted", params: params}) do
    # Handle "before" step immediately
    {:ok, notification} = create_notification("metric_deleted", params, "before")
    send_discord_notification(notification, "metric_deleted", params, "before")

    # Get scheduled_at datetime, handling both string and DateTime inputs
    scheduled_at =
      case params[:scheduled_at] do
        %DateTime{} = dt ->
          dt

        string when is_binary(string) ->
          {:ok, dt, _} = DateTime.from_iso8601(string)
          dt
      end

    reminder_at = DateTime.add(scheduled_at, -3, :day)

    # Schedule reminder notification (3 days before)
    job_args =
      %{
        action: "metric_deleted",
        params: params,
        step: "reminder"
      }
      |> Sanbase.Notifications.Workers.CreateNotification.new(scheduled_at: reminder_at)

    Oban.insert(@oban_conf_name, job_args)

    # Schedule after notification (on scheduled_at)
    job_args =
      %{
        action: "metric_deleted",
        params: params,
        step: "after"
      }
      |> Sanbase.Notifications.Workers.CreateNotification.new(scheduled_at: scheduled_at)

    Oban.insert(@oban_conf_name, job_args)

    {:ok, notification}
  end

  def handle_notification(%{action: "manual", params: params}) do
    channels =
      []
      |> maybe_add_channel(params[:email_text], "email")
      |> maybe_add_channel(params[:discord_text], "discord")

    {:ok, notification} = create_notification("manual", params, "all", channels)
    send_discord_notification(notification, "manual", params, "all")
    maybe_send_email_notification(notification, "manual", params, "all")

    {:ok, notification}
  end

  def handle_notification(%Notification{} = notification) do
    send_discord_notification(
      notification,
      notification.action,
      notification.params,
      notification.step
    )

    maybe_send_email_notification(
      notification,
      notification.action,
      notification.params,
      notification.step
    )

    {:ok, notification}
  end

  def create_notification(action, params, step, channels \\ nil) do
    %Notification{}
    |> Notification.changeset(%{
      action: action,
      params: params,
      channels: channels || @default_channels[action],
      step: step
    })
    |> Repo.insert()
  end

  defp mark_processed(notification, channel) do
    notification
    |> Notification.mark_channel_processed(channel)
    |> Repo.update()
  end

  def send_discord_notification(notification, action, params, step) do
    if "discord" in notification.channels do
      content =
        if action == "manual" do
          params.discord_text
        else
          TemplateRenderer.render_content(%{
            action: action,
            params: params,
            step: step,
            channel: "discord"
          })
        end

      webhook = Config.module_get(DiscordClient, :webhook)

      Task.async(fn ->
        case discord_client().send_message(webhook, content, []) do
          :ok -> mark_processed(notification, :discord)
          error -> error
        end
      end)
    end
  end

  def maybe_send_email_notification(notification, action, params, step) do
    if "email" in notification.channels do
      content =
        if action == "manual" do
          params.email_text
        else
          TemplateRenderer.render_content(%{
            action: action,
            params: params,
            step: step,
            channel: "email"
          })
        end

      Task.async(fn ->
        mailjet_api().send_to_list(:metric_updates, params.email_subject, content, [])
        |> case do
          :ok -> mark_processed(notification, :email)
          error -> error
        end
      end)
    end
  end

  # Helper function to conditionally add channels
  defp maybe_add_channel(channels, nil, _channel), do: channels
  defp maybe_add_channel(channels, "", _channel), do: channels
  defp maybe_add_channel(channels, _text, channel), do: [channel | channels]

  def discord_client do
    Application.get_env(:sanbase, :discord_client, DiscordClient)
  end

  def mailjet_api do
    Application.get_env(:sanbase, :mailjet_api, Sanbase.Email.MailjetApi)
  end
end
