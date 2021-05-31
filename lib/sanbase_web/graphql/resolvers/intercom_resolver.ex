defmodule SanbaseWeb.Graphql.Resolvers.IntercomResolver do
  import Norm

  alias Sanbase.Intercom.UserEvent
  alias Sanbase.Clickhouse.ApiCallData

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

  def api_metric_distribution(_, _, _) do
    {:ok, ApiCallData.api_metric_distribution()}
  end

  def api_metric_distribution_per_user(_, _, _) do
    {:ok, ApiCallData.api_metric_distribution_per_user()}
  end

  def track_events(_, %{events: events}, %{context: %{auth: %{current_user: user}}}) do
    if valid_events?(events) do
      events =
        events
        |> Enum.map(fn %{"event_name" => event_name, "created_at" => created_at} = event ->
          %{
            event_name: event_name,
            created_at:
              Sanbase.DateTimeUtils.from_iso8601!(created_at) |> DateTime.truncate(:second),
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
      selection(
        schema(%{
          "event_name" => spec(is_binary()),
          "created_at" => spec(is_binary()),
          "metadata" => spec(is_map())
        }),
        ["event_name", "created_at"]
      )

    valid?(event, event_schema)
  end
end
