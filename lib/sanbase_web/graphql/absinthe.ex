defmodule SanbaseWeb.Graphql.Absinthe do
  def before_send(conn, %Absinthe.Blueprint{} = blueprint) do
    # Currently only printing - could be put into cache somehow and retrieved
    IO.inspect("============================================================")
    IO.inspect(blueprint.result, limit: :infinity)
    IO.inspect("============================================================")
    conn
  end
end
