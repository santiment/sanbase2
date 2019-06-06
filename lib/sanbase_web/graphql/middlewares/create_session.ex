defmodule SanbaseWeb.Graphql.Middlewares.CreateSession do
  @behaviour Absinthe.Middleware

  alias Absinthe.Resolution

  def call(%Resolution{value: %{token: token, user: _user}} = resolution, _) do
    Map.update!(resolution, :context, fn ctx ->
      ctx
      |> Map.put(:create_session, true)
      |> Map.put(:auth_token, token)
    end)
  end

  def call(resolution, _), do: resolution
end
