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

  def handle_event({:ok, user_id}, event_type, data)
      when event_type in [:is_subscribed_monthly_newsletter, :is_subscribed_weekly_newsletter] do
    event_type =
      cond do
        event_type == :is_subscribed_monthly_newsletter and data[event_type] == true ->
          :subscribe_monthly_newsletter

        event_type == :is_subscribed_monthly_newsletter and data[event_type] == false ->
          :unsubscribe_monthly_newsletter

        event_type == :is_subscribed_weekly_newsletter and data[event_type] == true ->
          :subscribe_weekly_newsletter

        event_type == :is_subscribed_weekly_newsletter and data[event_type] == false ->
          :unsubscribe_weekly_newsletter
      end

    %{
      event_type: event_type,
      user_id: user_id
    }
    |> notify()
  end

  def handle_event({:ok, user_id}, :is_subscribed_metric_updates, data) do
    event_type =
      case data[:is_subscribed_metric_updates] do
        true -> :subscribe_metric_updates
        false -> :unsubscribe_metric_updates
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
