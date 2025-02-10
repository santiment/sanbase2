defmodule SanbaseWeb.Graphql.Resolvers.UserChartConfigurationResolver do
  @moduledoc false
  alias Sanbase.Accounts.User
  alias Sanbase.Chart.Configuration

  require Logger

  def chart_configurations(%User{} = user, _args, _context) do
    # Querying user_id is same as the queried user_id so it can access private data
    {:ok, Configuration.user_configurations(user.id, user.id)}
  end

  def public_chart_configurations(%User{} = user, _args, _resolution) do
    {:ok, Configuration.user_configurations(user.id, nil)}
  end
end
