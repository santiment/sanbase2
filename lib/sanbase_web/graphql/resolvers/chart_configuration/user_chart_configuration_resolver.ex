defmodule SanbaseWeb.Graphql.Resolvers.UserChartConfigurationResolver do
  require Logger

  alias Sanbase.Auth.User

  def chart_configurations(%User{} = user, _args, _context) do
    # Querying user_id is same as the queried user_id so it can access private data
    {:ok, Sanbase.Chart.Configuration.user_configurations(user.id, user.id)}
  end

  def public_chart_configurations(%User{} = user, _args, _resolution) do
    {:ok, Sanbase.Chart.Configuration.user_configurations(user.id, nil)}
  end
end
