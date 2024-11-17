defmodule Sanbase.Notifications.Workers.CreateNotification do
  use Oban.Worker, queue: :notifications

  alias Sanbase.Notifications.Handler

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"action" => action, "params" => params, "step" => step}}) do
    with {:ok, notification} <- Handler.create_notification(action, params, step) do
      Handler.send_discord_notification(notification, action, params, step)

      {:ok, notification}
    end
  end
end
