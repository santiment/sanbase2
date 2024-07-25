defmodule SanbaseWeb.Graphql.Resolvers.FeaturedItemResolver do
  require Logger

  import SanbaseWeb.Graphql.Helpers.Utils, only: [transform_user_trigger: 1]

  alias Sanbase.FeaturedItem

  def insights(_root, %{} = args, _context) do
    {:ok, FeaturedItem.insights(page: args.page, page_size: args.page_size)}
  end

  def watchlists(_root, %{} = args, _context) do
    {:ok, FeaturedItem.watchlists(args)}
  end

  def screeners(_root, _args, _context) do
    {:ok, FeaturedItem.watchlists(%{is_screener: true})}
  end

  def user_triggers(_root, _args, _context) do
    {:ok, FeaturedItem.user_triggers() |> Enum.map(&transform_user_trigger/1)}
  end

  def chart_configurations(_root, _args, _context) do
    {:ok, FeaturedItem.chart_configurations()}
  end

  def table_configurations(_root, _args, _context) do
    {:ok, FeaturedItem.table_configurations()}
  end

  def dashboards(_root, _args, _context) do
    {:ok, FeaturedItem.dashboards()}
  end

  def queries(_root, _args, _context) do
    {:ok, FeaturedItem.queries()}
  end
end
