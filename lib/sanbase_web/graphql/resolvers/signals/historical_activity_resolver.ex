defmodule SanbaseWeb.Graphql.Resolvers.SignalsHistoricalActivityResolver do
  import SanbaseWeb.Graphql.Helpers.Utils, only: [transform_user_trigger: 1]

  alias Sanbase.Signal.HistoricalActivity

  require Logger

  def fetch_historical_activity_for(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    case HistoricalActivity.fetch_historical_activity_for(current_user, args) do
      {:ok, %{activity: activity} = result} ->
        activity =
          activity
          |> Enum.map(fn %{user_trigger: ut} = elem ->
            elem
            |> Map.from_struct()
            |> Map.delete(:user_trigger)
            |> Map.put(:trigger, Map.get(transform_user_trigger(ut), :trigger))
          end)

        {:ok, %{result | activity: activity}}

      {:error, error} ->
        {:error, error}
    end
  end
end
