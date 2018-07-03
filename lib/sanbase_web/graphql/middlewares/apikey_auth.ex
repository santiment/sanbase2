defmodule SanbaseWeb.Graphql.Middlewares.ApikeyAuth do
  @moduledoc """
  Authenticate that the request contains a valid Apikey in the Authorization header
  and that the user has enough san tokens to access the data. If the san tokens
  are not specified it is assumed that 0 tokens are required.

  Example:

      query do
        field :project, :project do
          arg :id, non_null(:id)

          middleware SanbaseWeb.Graphql.Middlewares.Apikey, san_tokens: 200

          resolve &ProjectResolver.project/3
        end
      end

  This is going to require 200 SAN tokens to access the project query.
  """
  @behaviour Absinthe.Middleware

  alias SanbaseWeb.Graphql.Middlewares.Helpers
  alias Absinthe.Resolution

  @doc ~s"""
  Decides whether the apikey has access or not.

  The user that issued the apikey must have accepted the privacy policy in order to
  access resources that require apikey authentication.

  The user also must have the required number of SAN tokens to access some resources.
  The queries and mutations that require such SAN balance check provide a special
  configuration.
  """
  def call(
        %Resolution{context: %{auth: %{auth_method: :apikey, current_user: current_user}}} =
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
