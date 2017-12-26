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
  @behavior Absinthe.Middleware

  alias Absinthe.Resolution
  alias Sanbase.Auth.User

  def call(%Resolution{context: %{auth: %{auth_method: :user_token, current_user: current_user}}} = resolution, config) do
    required_san_tokens = Keyword.get(config, :san_tokens, 0)

    if has_enough_san_tokens?(current_user, required_san_tokens) do
      resolution
    else
      resolution
      |> Resolution.put_result({:error, :unauthorized})
    end
  end

  def call(resolution, _) do
    resolution
    |> Resolution.put_result({:error, :unauthorized})
  end

  defp has_enough_san_tokens?(_, 0), do: true

  defp has_enough_san_tokens?(current_user, san_tokens) do
    User.san_balance(current_user) >= san_tokens
  end
end
