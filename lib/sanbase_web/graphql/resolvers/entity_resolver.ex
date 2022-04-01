defmodule SanbaseWeb.Graphql.Resolvers.EntityResolver do
  def get_most_voted(_root, args, _resolution) do
    type = Map.get(args, :type)

    opts = [
      page: Map.get(args, :page, 1),
      page_size: Map.get(args, :page_size, 10),
      cursor: Map.get(args, :cursor)
    ]

    Sanbase.Entity.get_most_voted(type, opts)
  end

  def get_most_recent(_root, args, _resolution) do
    type = Map.get(args, :type)

    opts = [
      page: Map.get(args, :page, 1),
      page_size: Map.get(args, :page_size, 10),
      cursor: Map.get(args, :cursor)
    ]

    Sanbase.Entity.get_most_recent(type, opts)
  end
end
