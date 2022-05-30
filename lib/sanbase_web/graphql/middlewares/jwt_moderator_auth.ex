defmodule SanbaseWeb.Graphql.Middlewares.JWTModeratorAuth do
  @moduledoc """
  Authenticate that the request contains a valid JWT token and that the user
  has moderator permissions

  Example:

    query do
      field :moderate_set_deleted, :boolean do
        arg(:entity_id, non_null(:integer))
        arg(:entity_type, non_null(:entity_type))

        middleware(SanbaseWeb.Graphql.Middlewares.JWTModeratorAuth)

        resolve &ModerationResolver.moderate_set_deleted/3
      end
    end

  """
  @behaviour Absinthe.Middleware

  alias Absinthe.Resolution

  @doc ~s"""
  Give access only if the user has a moderator role
  """
  def call(
        %Resolution{
          context: %{
            is_moderator: is_moderator,
            auth: %{auth_method: auth_method}
          }
        } = resolution,
        _opts
      ) do
    case is_moderator == true and auth_method == :user_token do
      true ->
        resolution

      false ->
        resolution
        |> Resolution.put_result({:error, :unauthorized})
    end
  end

  def call(resolution, _), do: Resolution.put_result(resolution, {:error, :unauthorized})
end
