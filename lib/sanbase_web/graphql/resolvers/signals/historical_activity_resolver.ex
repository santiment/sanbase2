defmodule SanbaseWeb.Graphql.Resolvers.SignalsHistoricalActivityResolver do
  import SanbaseWeb.Graphql.Helpers.Utils, only: [replace_user_trigger_with_trigger: 1]

  alias Sanbase.Signal.HistoricalActivity

  require Logger

  def fetch_historical_activity_for(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    case HistoricalActivity.fetch_historical_activity_for(current_user, args) do
      {:ok, %{activity: activity} = result} ->
        {:ok, %{result | activity: replace_user_trigger_with_trigger(activity)}}

      {:error, error} ->
        {:error, error}
    end
  end
end
