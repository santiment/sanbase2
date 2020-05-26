defmodule Sanbase.Timeline.Cursor do
  import Ecto.Query

  def filter_by_cursor(query, :before, datetime) do
    from(
      event in query,
      where: event.inserted_at < ^DateTime.to_naive(datetime)
    )
  end

  def filter_by_cursor(query, :after, datetime) do
    from(
      event in query,
      where: event.inserted_at > ^DateTime.to_naive(datetime)
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
end
