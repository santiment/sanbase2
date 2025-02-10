defmodule Sanbase.Email.MailjetEventEmitter do
  @moduledoc false
  use Sanbase.EventBus.EventEmitter

  @topic :user_events
  def topic, do: @topic

  def handle_event({:error, _}, _event_type, _extra_args), do: :ok

  def handle_event({:ok, user_id}, :is_subscribed_biweekly_report, data) do
    event_type =
      if data[:is_subscribed_biweekly_report] do
        :subscribe_biweekly_report
      else
        :unsubscribe_biweekly_report
      end

    notify(%{event_type: event_type, user_id: user_id})
  end

  def handle_event({:ok, user_id}, :is_subscribed_monthly_newsletter, data) do
    event_type =
      if data[:is_subscribed_monthly_newsletter] do
        :subscribe_monthly_newsletter
      else
        :unsubscribe_monthly_newsletter
      end

    notify(%{event_type: event_type, user_id: user_id})
  end

  def handle_event({:ok, user_id}, :is_subscribed_metric_updates, data) do
    event_type =
      if data[:is_subscribed_metric_updates] do
        :subscribe_metric_updates
      else
        :unsubscribe_metric_updates
      end

    notify(%{event_type: event_type, user_id: user_id})
  end

  defp notify(data) do
    Sanbase.EventBus.notify(%{topic: @topic, data: data})
    :ok
  end
end
