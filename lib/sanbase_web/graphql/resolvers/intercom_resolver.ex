defmodule SanbaseWeb.Graphql.Resolvers.IntercomResolver do
  alias Sanbase.Intercom.UserEvent
  import Norm

  def get_attributes_for_users(_, %{users: users, days: days} = args, _) do
    from = Map.get(args, :from, Sanbase.DateTimeUtils.days_ago(days))
    to = Map.get(args, :to, Timex.now())

    {:ok, Sanbase.Intercom.UserAttributes.get_attributes_for_users(users, from, to)}
  end

  def get_events_for_users(_, %{users: users, days: days} = args, _) do
    from = Map.get(args, :from, Sanbase.DateTimeUtils.days_ago(days))
    to = Map.get(args, :to, Timex.now())

    {:ok, UserEvent.get_events_for_users(users, from, to)}
  end

  def track_events(_, %{events: events}, %{context: %{auth: %{current_user: user}}}) do
    if valid_events?(events) do
      events =
        events
        |> Enum.map(fn %{"event_name" => event_name, "created_at" => created_at} = event ->
          %{
            event_name: event_name,
            created_at: Sanbase.DateTimeUtils.from_iso8601!(created_at),
            user_id: user.id,
            metadata: event["metadata"],
            inserted_at: Timex.now() |> DateTime.truncate(:second),
            updated_at: Timex.now() |> DateTime.truncate(:second)
          }
        end)

      UserEvent.create(events)

      {:ok, true}
    else
      {:error, "List of events contains invalid events"}
    end
  end

  def valid_events?(events) do
    Enum.all?(events, &valid_event?/1)
  end

  def valid_event?(event) do
    event_schema =
      schema(%{
        "event_name" => spec(is_binary()),
        "created_at" => spec(&match?(%DateTime{}, &1)),
        "metadata" => spec(is_map())
      })

    valid?(event, event_schema)
  end
end
