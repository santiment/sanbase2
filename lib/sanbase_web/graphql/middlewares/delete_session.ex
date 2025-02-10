defmodule SanbaseWeb.Graphql.Middlewares.DeleteSession do
  @moduledoc false
  @behaviour Absinthe.Middleware

  alias Absinthe.Resolution

  def call(%Resolution{value: true} = resolution, _) do
    Map.update!(resolution, :context, fn context ->
      Map.put(context, :delete_session, true)
    end)
  end

  def call(resolution, _), do: resolution
end
