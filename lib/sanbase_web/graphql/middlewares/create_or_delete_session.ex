defmodule SanbaseWeb.Graphql.Middlewares.CreateOrDeleteSession do
  @moduledoc false
  @behaviour Absinthe.Middleware

  alias Absinthe.Resolution

  def call(%Resolution{value: %{access_token: access_token, refresh_token: refresh_token, user: _user}} = resolution, _) do
    Map.update!(resolution, :context, fn context ->
      context
      |> Map.put(:create_session, true)
      |> Map.put(:access_token, access_token)
      |> Map.put(:refresh_token, refresh_token)
    end)
  end

  def call(%Resolution{value: %{success: true}} = resolution, _) do
    Map.update!(resolution, :context, fn context ->
      Map.put(context, :delete_session, true)
    end)
  end

  def call(resolution, _), do: resolution
end
