defmodule SanbaseWeb.Graphql.Resolvers.EntityResolver do
  def get_most_voted(_root, args, resolution) do
    types = Map.get(args, :types) || [Map.get(args, :type)]

    opts =
      [
        page: Map.get(args, :page, 1),
        page_size: Map.get(args, :page_size, 10),
        cursor: Map.get(args, :cursor)
      ]
      |> maybe_add_current_user_data_only(args, resolution)

    Sanbase.Entity.get_most_voted(types, opts)
  end

  def get_most_recent(_root, args, resolution) do
    types = Map.get(args, :types) || [Map.get(args, :type)]

    opts =
      [
        page: Map.get(args, :page, 1),
        page_size: Map.get(args, :page_size, 10),
        cursor: Map.get(args, :cursor)
      ]
      |> maybe_add_current_user_data_only(args, resolution)

    Sanbase.Entity.get_most_recent(types, opts)
  end

  defp maybe_add_current_user_data_only(opts, args, resolution) do
    with true <- Map.get(args, :current_user_data_only, false),
         user_id when is_integer(user_id) <-
           get_in(resolution.context.auth, [:current_user, Access.key(:id)]) do
      Keyword.put(opts, :current_user_data_only, user_id)
    else
      _ -> opts
    end
  end
end
