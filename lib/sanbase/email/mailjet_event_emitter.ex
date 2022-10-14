defmodule Sanbase.Email.MailjetEventEmitter do
  use Sanbase.EventBus.EventEmitter

  @topic :user_events
  def topic(), do: @topic

  def handle_event({:error, _}, _event_type, _extra_args), do: :ok

  def handle_event({:ok, user_id}, :is_subscribed_biweekly_report, data) do
    event_type =
      case data[:is_subscribed_biweekly_report] do
        true -> :subscribe_biweekly_report
        false -> :unsubscribe_biweekly_report
      end

    %{
      event_type: event_type,
      user_id: user_id
    }
    |> notify()
  end

  def handle_event({:ok, user_id}, :is_subscribed_monthly_newsletter, data) do
    event_type =
      case data[:is_subscribed_monthly_newsletter] do
        true -> :subscribe_monthly_newsletter
        false -> :unsubscribe_monthly_newsletter
      end

    %{
      event_type: event_type,
      user_id: user_id
    }
    |> notify()
  end

  defp notify(data) do
    Sanbase.EventBus.notify(%{topic: @topic, data: data})
    :ok
  end
end
