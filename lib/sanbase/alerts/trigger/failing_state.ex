defmodule Sanbase.Alert.Trigger.FailingState do
  @moduledoc ~s"""
  Tracks alerts whose sends keep failing and decides when to auto-disable
  them. The state lives in the `failing_since`, `failed_attempts`,
  `consecutive_failed_days` and `last_failed_on` fields of the trigger embed.
  """

  alias Sanbase.Alert.Trigger

  @consecutive_failed_days_before_deactivation 7

  @doc ~s"""
  Compute the trigger's next failing state from a send round: a success
  clears it, delivery failures extend it, anything else keeps it unchanged.
  """
  def next(%Trigger{}, %{any_success?: true}) do
    %{failing_since: nil, failed_attempts: 0, consecutive_failed_days: 0, last_failed_on: nil}
  end

  def next(%Trigger{} = trigger, %{any_delivery_failure?: true} = results) do
    today = Date.utc_today()

    consecutive_failed_days =
      cond do
        trigger.last_failed_on == today ->
          max(trigger.consecutive_failed_days || 0, 1)

        trigger.last_failed_on == Date.add(today, -1) ->
          (trigger.consecutive_failed_days || 0) + 1

        # First failure, or the chain was broken by a day without failures
        true ->
          1
      end

    %{
      failing_since: trigger.failing_since || DateTime.utc_now() |> DateTime.truncate(:second),
      failed_attempts: (trigger.failed_attempts || 0) + results.delivery_failures_count,
      consecutive_failed_days: consecutive_failed_days,
      last_failed_on: today
    }
  end

  # Explicit match instead of a catch-all so a malformed results map crashes
  # rather than silently keeping the state.
  def next(%Trigger{} = trigger, %{any_success?: false, any_delivery_failure?: false}) do
    Map.take(trigger, [
      :failing_since,
      :failed_attempts,
      :consecutive_failed_days,
      :last_failed_on
    ])
  end

  @doc ~s"""
  Send failures that count towards the failing state. The daily alerts limit
  does not mean the destination is broken, so it does not count.
  """
  def delivery_failure?({:error, %{reason: :alerts_limit_reached}}), do: false
  def delivery_failure?({:error, _}), do: true
  def delivery_failure?(_result), do: false

  @doc ~s"""
  Deactivate an alert that failed on 7+ days in a row with no successful send
  in between. A day without any failed send breaks the chain.
  """
  def deactivate?(%{consecutive_failed_days: consecutive_failed_days}) do
    (consecutive_failed_days || 0) >= @consecutive_failed_days_before_deactivation
  end
end
