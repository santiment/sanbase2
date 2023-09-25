defmodule SanbaseWeb.Graphql.Middlewares.UserAuth do
  @moduledoc """
  Authenticate that the request contains a valid user

  """
  @behaviour Absinthe.Middleware

  alias Absinthe.Resolution
  alias SanbaseWeb.Graphql.Middlewares.Helpers

  @doc ~s"""
  Decides whether the user has access or not.

  The user must have accepted the privacy policy in order to access resources.
  This allows both API key authentication and JWT authentication
  """
  def call(
        %Resolution{
          context: %{
            auth: %{
              current_user: current_user
            }
          }
        } = resolution,
        opts
      ) do
    Helpers.handle_user_access(resolution, current_user, opts)
  end

  def call(resolution, _), do: Resolution.put_result(resolution, {:error, :unauthorized})
end
