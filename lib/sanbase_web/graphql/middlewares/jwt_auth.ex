defmodule SanbaseWeb.Graphql.Middlewares.JWTAuth do
  @moduledoc """
  Authenticate that the request contains a valid JWT token.

  Example:
    query do
      field :project, :project do
        arg :id, non_null(:id)

        middleware(SanbaseWeb.Graphql.Middlewares.JWTAuth)

        resolve &ProjectResolver.project/3
      end
    end
  """
  @behaviour Absinthe.Middleware

  alias Absinthe.Resolution
  alias SanbaseWeb.Graphql.Middlewares.Helpers

  @doc ~s"""
  Decides whether the user has access or not.

  The user must have accepted the privacy policy in order to access resources
  that require JWT authentication. There are some mutations (the mutation for
  accepting the privacy policy) that should not fail if the privacy policy
  is not accepted - they provide a special configuration to achieve this
  behaviour
  """
  def call(%Resolution{context: %{auth: %{auth_method: :user_token, current_user: current_user}}} = resolution, opts) do
    Helpers.handle_user_access(resolution, current_user, opts)
  end

  def call(resolution, _), do: Resolution.put_result(resolution, {:error, :unauthorized})
end
