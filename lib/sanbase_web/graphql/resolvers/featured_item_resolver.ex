defmodule SanbaseWeb.Graphql.Resolvers.FeaturedItemResolver do
  require Logger

  alias Sanbase.FeaturedItem

  def insights(_root, _args, _context) do
    {:ok, FeaturedItem.insights()}
  end

  def watchlists(_root, _args, _context) do
    {:ok, FeaturedItem.watchlists()}
  end

  def user_triggers(_root, _args, _context) do
    {:ok, FeaturedItem.user_triggers()}
  end
end
