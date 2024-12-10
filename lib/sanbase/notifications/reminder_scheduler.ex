defmodule Sanbase.Notifications.ReminderScheduler do
  @moduledoc """
  Handles the scheduling logic for metric deletion reminders.
  The reminder schedule is as follows:
  - Less than 30 days: one reminder 3 days before
  - Between 30 days and 2 months: reminders at 14 days and 3 days before
  - More than 2 months: monthly reminders and 3 days before
  """

  def calculate_reminder_dates(scheduled_at) do
    now = DateTime.utc_now()
    days_until_deletion = DateTime.diff(scheduled_at, now, :day)

    cond do
      # If scheduled date is in the past or today, return empty list
      days_until_deletion <= 0 ->
        []

      # Less than 30 days - just 3 days before
      days_until_deletion < 30 ->
        [DateTime.add(scheduled_at, -3, :day)]

      # Between 30 days and 2 months - 14 days and 3 days before
      days_until_deletion <= 60 ->
        [
          DateTime.add(scheduled_at, -14, :day),
          DateTime.add(scheduled_at, -3, :day)
        ]

      # More than 2 months - monthly + 3 days before
      true ->
        monthly_reminders = create_monthly_reminders(now, scheduled_at)
        final_reminder = [DateTime.add(scheduled_at, -3, :day)]

        (monthly_reminders ++ final_reminder)
        |> Enum.uniq()
        |> Enum.sort_by(&DateTime.to_unix/1)
    end
    |> Enum.map(&DateTime.truncate(&1, :second))
  end

  defp create_monthly_reminders(now, scheduled_at) do
    days_until_deletion = DateTime.diff(scheduled_at, now, :day)

    0..div(days_until_deletion, 30)
    |> Enum.map(fn months ->
      DateTime.add(now, months * 30, :day)
    end)
  end
end
