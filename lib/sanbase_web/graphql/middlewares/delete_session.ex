defmodule SanbaseWeb.Graphql.Middlewares.DeleteSession do
  @behaviour Absinthe.Middleware

  alias Absinthe.Resolution

  def call(%Resolution{value: %{logout_success: true}} = resolution, _) do
    Map.update!(resolution, :context, fn ctx ->
      Map.put(ctx, :delete_session, true)
    end)
  end

  def call(resolution, _), do: resolution
end
