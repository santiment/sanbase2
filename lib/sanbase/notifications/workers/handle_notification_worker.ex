defmodule Sanbase.Notifications.Workers.HandleNotificationWorker do
  @moduledoc false
  use Oban.Worker, queue: :reminder_notifications_queue

  alias Sanbase.Notifications.Handler

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Handler.handle_notification(%{
      action: args["action"],
      params: args["params"],
      metric_registry_id: args["metric_registry_id"],
      step: args["step"]
    })

    :ok
  end
end
