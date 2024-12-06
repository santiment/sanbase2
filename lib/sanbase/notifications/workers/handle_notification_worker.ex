defmodule Sanbase.Notifications.Workers.HandleNotificationWorker do
  use Oban.Worker, queue: :reminder_notifications_queue

  alias Sanbase.Notifications.Handler

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{
      action: args["action"],
      params: args["params"],
      metric_registry_id: args["metric_registry_id"],
      step: args["step"]
    }
    |> Handler.handle_notification()

    :ok
  end
end
