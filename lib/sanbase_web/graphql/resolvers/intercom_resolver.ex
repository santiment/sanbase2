defmodule SanbaseWeb.Graphql.Resolvers.IntercomResolver do
  import Norm
  import Sanbase.DateTimeUtils, only: [from_iso8601!: 1]

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
    ApiCallData.api_metric_distribution()
  end

  def api_metric_distribution_per_user(_, _, _) do
    ApiCallData.api_metric_distribution_per_user()
  end

  def track_events(_, %{events: events} = params, resolution) do
    %{user_id: user_id, anonymous_user_id: anonymous_user_id} =
      get_identification_fields(resolution, params)

    if valid_events?(events) do
      events =
        events
        |> Enum.map(fn %{"event_name" => event_name, "created_at" => created_at} = event ->
          %{
            event_name: event_name,
            created_at: from_iso8601!(created_at) |> DateTime.truncate(:second),
            metadata: event["metadata"],
            inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
            updated_at: DateTime.utc_now() |> DateTime.truncate(:second),
            user_id: user_id,
            anonymous_user_id: anonymous_user_id
          }
        end)

      is_authenticated = user_id != 0

      UserEvent.create(events, is_authenticated)

      {:ok, true}
    else
      {:error, "List of events contains invalid events"}
    end
  end

  # Private functions

  # Get the user_id and anonymous_user_id. They cannot be NULL as primary key
  # fields in Clickhouse cannot be NULL. use 0 and empty string when these fields
  # need to not be filled
  defp get_identification_fields(%{context: %{auth: %{current_user: user}}}, _params) do
    %{user_id: user.id, anonymous_user_id: ""}
  end

  defp get_identification_fields(_resolution, params) do
    case params do
      %{anonymous_user_id: anonymous_user_id} when byte_size(anonymous_user_id) >= 28 ->
        %{user_id: 0, anonymous_user_id: anonymous_user_id}

      _ ->
        {:error,
         "Not authenticated requests to trackEvents must include `anonymous_user_id` field which is at least 28 characters long"}
    end
  end

  defp valid_events?(events) do
    Enum.all?(events, &valid_event?/1)
  end

  defp valid_event?(event) do
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
