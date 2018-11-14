defmodule SanbaseWeb.Graphql.Complexity.SocialDataComplexity do
  require Logger

  @doc ~S"""
  Internal services use basic authentication. Return complexity = 0 to allow them
  to access everything without limits.
  """
  def trending_words(_, _, %Absinthe.Complexity{context: %{auth: %{auth_method: :basic}}}) do
    0
  end
end
