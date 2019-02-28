defmodule SanbaseWeb.Graphql.Resolvers.SignalsHistoricalActivityResolver do
  require Logger

  alias Sanbase.Auth.User
  alias Sanbase.Signals.HistoricalActivity

  def fetch_historical_activity_for(%User{} = user, args, _resolution) do
    case HistoricalActivity.fetch_historical_activity_for(user, args) do
      {:ok, activity} ->
        {:ok, activity}

      {:error, error} ->
        {:error, error}
    end
  end
end
