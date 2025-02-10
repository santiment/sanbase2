defmodule Sanbase.Timeline.Cursor do
  @moduledoc """
  Cursor based pagination for timeline events.
  Return maximum of 6 months of timeline events data.
  """

  import Ecto.Query

  def filter_by_min_dt(query) do
    min_dt = six_months_ago()

    from(
      event in query,
      where: event.inserted_at >= ^min_dt
    )
  end

  def filter_by_cursor(query, :before, datetime) do
    min_dt = six_months_ago()

    from(
      event in query,
      where: event.inserted_at >= ^min_dt and event.inserted_at <= ^datetime
    )
  end

  def filter_by_cursor(query, :after, datetime) do
    min_dt = six_months_ago()

    datetime =
      case DateTime.compare(datetime, min_dt) do
        :gt -> datetime
        _ -> min_dt
      end

    from(
      event in query,
      where: event.inserted_at >= ^datetime
    )
  end

  def wrap_events_with_cursor([]), do: {:ok, %{events: [], cursor: %{}}}

  def wrap_events_with_cursor(events) do
    before_datetime = events |> List.last() |> Map.get(:inserted_at)
    after_datetime = events |> List.first() |> Map.get(:inserted_at)

    {:ok,
     %{
       events: events,
       cursor: %{
         before: before_datetime,
         after: after_datetime
       }
     }}
  end

  defp six_months_ago do
    Timex.shift(DateTime.utc_now(), months: -6)
  end
end
