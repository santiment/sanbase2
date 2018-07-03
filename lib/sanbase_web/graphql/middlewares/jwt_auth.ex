defmodule SanbaseWeb.Graphql.Middlewares.JWTAuth do
  @moduledoc """
  Authenticate that the request contains a valid JWT token and that the user has
  enough san tokens to access the data. If the san tokens are not specified
  it is assumed that 0 tokens are required.

  Example:

      query do
        field :project, :project do
          arg :id, non_null(:id)

          middleware SanbaseWeb.Graphql.Middlewares.JWTAuth, san_tokens: 200

          resolve &ProjectResolver.project/3
        end
      end

  This is going to require 200 SAN tokens to access the project query.
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

  The user also must have the required number of SAN tokens to access some resources.
  The queries and mutations that require such SAN balance check provide a special
  configuration.
  """
  def call(
        %Resolution{context: %{auth: %{auth_method: :user_token, current_user: current_user}}} =
          resolution,
        config
      ) do
    Helpers.handle_user_access(current_user, config, resolution)
  end

  def call(resolution, _) do
    resolution
    |> Resolution.put_result({:error, :unauthorized})
  end
end
