defmodule Sanbase.Notifications.ReminderScheduler do
  @moduledoc """
  Handles the scheduling logic for metric deletion reminders.
  The reminder schedule is as follows:
  - Less than or equal to 31 days: one reminder 3 days before
  - Between 31 days and 2 months: reminders at 14 days and 3 days before
  - More than 2 months: monthly reminders and 3 days before
  """

  def calculate_reminder_dates(scheduled_at) do
    now = DateTime.utc_now()
    days_until_deletion = DateTime.diff(scheduled_at, now, :day)

    cond_result =
      cond do
        # If scheduled date is in the past or today, return empty list
        days_until_deletion <= 0 ->
          []

        # Less than 31 days - just 3 days before
        days_until_deletion <= 31 ->
          [DateTime.add(scheduled_at, -3, :day)]

        # Between 31 days and 2 months - 14 days and 3 days before
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

    Enum.map(cond_result, &DateTime.truncate(&1, :second))
  end

  def create_monthly_reminders(now, scheduled_at) do
    now = DateTime.truncate(now, :second)
    scheduled_at = DateTime.truncate(scheduled_at, :second)

    Enum.reduce_while(Stream.iterate(1, &(&1 + 1)), [], fn months, acc ->
      reminder_date = DateTime.add(now, months * 30, :day)
      days_until_deletion = DateTime.diff(scheduled_at, reminder_date, :day)

      if days_until_deletion >= 30 do
        {:cont, [reminder_date | acc]}
      else
        {:halt, Enum.reverse(acc)}
      end
    end)
  end
end
