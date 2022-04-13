defmodule SanbaseWeb.Graphql.Resolvers.EntityResolver do
  import Sanbase.Utils.Transform, only: [maybe_apply_function: 2]
  import SanbaseWeb.Graphql.Helpers.Utils, only: [transform_user_trigger: 1]

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
    |> maybe_apply_function(&handle_result/1)
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
    |> maybe_apply_function(&handle_result/1)
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

  defp handle_result(list) do
    Enum.map(list, fn map ->
      case Map.to_list(map) do
        [{:user_trigger, entity}] -> %{:user_trigger => transform_user_trigger(entity)}
        _ -> map
      end
    end)
  end
end
