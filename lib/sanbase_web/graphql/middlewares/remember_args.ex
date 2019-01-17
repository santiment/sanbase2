defmodule SanbaseWeb.Graphql.Middlewares.RememberArgs do
  @moduledoc """
  Save arguments in context so they can be used in fields resolvers
  """
  alias Absinthe.Resolution

  def call(
        %Resolution{
          context: context,
          arguments: arguments
        } = resolution,
        _
      ) do
    %Resolution{resolution | context: Map.put(context, :arguments, arguments)}
  end
end
