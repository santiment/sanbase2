defmodule SanbaseWeb.Graphql.Resolvers.EntityResolver do
  def get_most_voted(_root, args, _resolution) do
    type = Map.get(args, :type)
    page = Map.get(args, :page, 1)
    page_size = Map.get(args, :page_size, 10)
    Sanbase.Entity.get_most_voted(type, page: page, page_size: page_size)
  end

  def get_most_recent(_root, args, _resolution) do
    type = Map.get(args, :type)
    page = Map.get(args, :page, 1)
    page_size = Map.get(args, :page_size, 10)
    Sanbase.Entity.get_most_recent(type, page: page, page_size: page_size)
  end
end
