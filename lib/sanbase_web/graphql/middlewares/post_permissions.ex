defmodule SanbaseWeb.Graphql.Middlewares.PostPermissions do
  @behaviour Absinthe.Middleware

  alias Absinthe.Resolution

  @allowed_fields_for_anon_users ["title", "shortDesc"]

  def call(%Resolution{context: %{auth: %{auth_method: :user_token}}} = resolution, _) do
    resolution
  end

  def call(resolution, _) do
    if has_not_allowed_fields?(resolution) do
      resolution
      |> Resolution.put_result({:error, :unauthorized})
    else
      resolution
    end
  end

  # Helper functions

  defp has_not_allowed_fields?(resolution) do
    requested_fields = requested_fields(resolution)

    Enum.any?(requested_fields, fn field ->
      field not in @allowed_fields_for_anon_users
    end)
  end

  defp requested_fields(resolution) do
    resolution.definition.selections
    |> Enum.map(&Map.get(&1, :name))
  end
end
