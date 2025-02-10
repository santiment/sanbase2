defmodule SanbaseWeb.Graphql.Resolvers.UserTableConfigurationResolver do
  @moduledoc false
  alias Sanbase.Accounts.User

  require Logger

  def chart_configurations(%User{} = user, _args, _context) do
    # Querying user_id is same as the queried user_id so it can access private data
    {:ok, Sanbase.TableConfiguration.user_table_configurations(user.id, user.id)}
  end

  def public_chart_configurations(%User{} = user, _args, _resolution) do
    {:ok, Sanbase.TableConfiguration.user_table_configurations(user.id, nil)}
  end
end
