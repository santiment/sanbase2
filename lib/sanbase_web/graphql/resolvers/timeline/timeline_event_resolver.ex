defmodule SanbaseWeb.Graphql.Resolvers.TimelineEventResolver do
  require Logger

  import SanbaseWeb.Graphql.Helpers.Utils, only: [transform_user_trigger: 1]
  alias Sanbase.Timeline.TimelineEvent

  def timeline_events(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    case TimelineEvent.events(current_user, args) do
      {:ok, %{events: events} = result} ->
        events =
          events
          |> Enum.map(fn
            %{user_trigger: ut} = elem when not is_nil(ut) ->
              elem
              |> Map.from_struct()
              |> Map.delete(:user_trigger)
              |> Map.put(:trigger, Map.get(transform_user_trigger(ut), :trigger))

            elem ->
              elem
          end)

        {:ok, %{result | events: events}}

      {:error, error} ->
        {:error, error}
    end
  end
end
