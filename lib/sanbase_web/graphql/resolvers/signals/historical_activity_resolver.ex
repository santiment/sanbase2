defmodule SanbaseWeb.Graphql.Resolvers.SignalsHistoricalActivityResolver do
  require Logger

  alias Sanbase.Signals.HistoricalActivity

  def fetch_historical_activity_for(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    case HistoricalActivity.fetch_historical_activity_for(current_user, args) do
      {:ok, activity} ->
        {:ok, activity}

      {:error, error} ->
        {:error, error}
    end
  end
end
