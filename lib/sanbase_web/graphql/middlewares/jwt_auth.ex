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
  alias Sanbase.Auth.User

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
    required_san_tokens = Keyword.get(config, :san_tokens, 0)
    allow_access = Keyword.get(config, :allow_access, false)

    with true <- allow_access?(current_user, allow_access),
         true <- has_enough_san_tokens?(current_user, required_san_tokens) do
      resolution
    else
      {:error, _message} = error ->
        resolution
        |> Resolution.put_result(error)
    end
  end

  def call(resolution, _) do
    resolution
    |> Resolution.put_result({:error, :unauthorized})
  end

  # Private functions

  defp has_enough_san_tokens?(_, 0), do: true

  defp has_enough_san_tokens?(current_user, san_tokens) do
    if Decimal.cmp(User.san_balance!(current_user), Decimal.new(san_tokens)) != :lt do
      true
    else
      {:error, "Insufficient SAN balance"}
    end
  end

  defp allow_access?(_current_user, true), do: true

  defp allow_access?(%User{privacy_policy_accepted: privacy_policy_accepted}, allow_access) do
    if allow_access || privacy_policy_accepted do
      true
    else
      {:error, "Access denied. Accept the privacy policy to activate your account."}
    end
  end
end
