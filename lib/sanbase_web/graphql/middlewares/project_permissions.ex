defmodule SanbaseWeb.Graphql.Middlewares.ProjectPermissions do
  @behaviour Absinthe.Middleware

  def call(%Resolution{context: %{auth: %{auth_method: :basic}}} = resolution, _) do
    resolution
  end

  def call(%Resolution{context: %{auth: %{auth_method: :user_token}}} = resolution, _) do
    resolution
  end
end
