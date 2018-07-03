defmodule SanbaseWeb.Graphql.Middlewares.ProjectPermissions do
  @behaviour Absinthe.Middleware

  alias Absinthe.Resolution

  def call(%Resolution{context: %{auth: %{auth_method: :basic}}} = resolution, _) do
    resolution
  end

  def call(%Resolution{context: %{auth: %{auth_method: method}}} = resolution, _)
      when method in [:user_token, :apikey] do
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
    not_allowed_fields = ["initial_ico", "icos"]

    requested_fields = requested_fields(resolution)

    Enum.any?(not_allowed_fields, fn field ->
      Map.has_key?(requested_fields, field)
    end)
  end

  defp requested_fields(resolution) do
    resolution.definition.selections
    |> Enum.map(&Map.get(&1, :name))
    |> Enum.into(%{}, fn field -> {field, true} end)
  end
end
