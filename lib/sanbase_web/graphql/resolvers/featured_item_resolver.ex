defmodule SanbaseWeb.Graphql.Resolvers.FeaturedItemResolver do
  require Logger

  import SanbaseWeb.Graphql.Helpers.Utils, only: [transform_user_trigger: 1]

  alias Sanbase.FeaturedItem

  def insights(_root, _args, _context) do
    {:ok, FeaturedItem.insights()}
  end

  def watchlists(_root, _args, _context) do
    {:ok, FeaturedItem.watchlists()}
  end

  def user_triggers(_root, _args, _context) do
    {:ok, FeaturedItem.user_triggers() |> Enum.map(&transform_user_trigger/1)}
  end
end
