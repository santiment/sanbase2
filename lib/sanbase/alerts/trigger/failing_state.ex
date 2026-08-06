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

  # Failures split by how they disable an alert. Email failures and telegram
  # rate limits count as neither - they can be on our side, not the client's.
  # :telegram_chat_not_found_404 is also excluded: telegram returns 404 for an
  # invalid bot token (our misconfiguration), not for a missing chat.
  @permanent_failure_reasons [
    :webhook_url_not_valid,
    :telegram_chat_not_found,
    :telegram_bot_blocked
  ]

  # A blocked-IP DNS resolution is a streak failure, not a permanent one -
  # resolvers can transiently return blocked addresses (e.g. DNS-level
  # ad blocking resolving to 127.0.0.1).
  @streak_failure_reasons [:webhook_send_fail, :webhook_url_resolves_to_blocked_ip]

  @doc ~s"""
  Failures proving the destination itself is broken - an invalid webhook URL
  or an unreachable telegram chat. They disable the alert on the spot.
  """
  def permanent_failure?({:error, %{reason: reason}}), do: reason in @permanent_failure_reasons
  def permanent_failure?(_result), do: false

  @doc ~s"""
  Possibly transient failures that count towards the failing state and
  disable the alert only after failing for 7 days in a row.
  """
  def delivery_failure?({:error, %{reason: reason}}), do: reason in @streak_failure_reasons
  def delivery_failure?(_result), do: false

  @doc ~s"""
  Disable the alert immediately - every send attempt of the round failed with
  a permanent error, so all its destinations are broken. If any channel
  delivered or failed transiently (email, rate limit), the alert is kept
  active.
  """
  def deactivate_now?(%{all_permanent_failures?: all_permanent_failures?}) do
    all_permanent_failures?
  end

  @doc ~s"""
  Deactivate an alert that failed on 7+ days in a row with no successful send
  in between. A day without any failed send breaks the chain.
  """
  def deactivate?(%{consecutive_failed_days: consecutive_failed_days}) do
    (consecutive_failed_days || 0) >= @consecutive_failed_days_before_deactivation
  end
end
