defmodule SanbaseWeb.Graphql.Middlewares.LoginSuccess do
  @behaviour Absinthe.Middleware

  alias Absinthe.Resolution

  def call(%Resolution{value: %{token: token, user: _user}} = resolution) do
    Map.update!(resolution, :context, fn ctx ->
      Map.put(ctx, :auth_token, token)
    end)
  end

  def call(resolution, _), do: resolution
end
