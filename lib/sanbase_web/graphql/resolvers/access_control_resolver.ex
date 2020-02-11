defmodule SanbaseWeb.Graphql.Resolvers.AccessControlResolver do
  def get_access_control(_root, _args, %{context: %{auth: %{subscription: subscription}}}) do
    # ...
  end

  def get_access_control(_root, _args, %{context: %{product: product}}) do
  end

  def get_access_control(_root, _args, _resolution) do
  end
end
