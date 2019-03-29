defmodule SanbaseWeb.Graphql.Absinthe do
  alias SanbaseWeb.Graphql.Cache

  def before_send(conn, %Absinthe.Blueprint{} = blueprint) do
    Cache.get_or_store(
      blueprint.execution.context.query_cache_key,
      fn -> blueprint.result end
    )

    conn
  end
end
