defmodule SanbaseWeb.Graphql.Middlewares.PostPermissions do
  @moduledoc false
  @behaviour Absinthe.Middleware

  alias Absinthe.Resolution
  alias SanbaseWeb.Graphql.Helpers.Utils

  @allowed_fields_for_anon_users [
    "id",
    "title",
    "shortDesc",
    "votes",
    "user",
    "createdAt",
    "updatedAt",
    "state",
    "readyState",
    "tags",
    "votedAt",
    "__typename"
  ]

  def call(%Resolution{context: %{auth: %{auth_method: :user_token}}} = resolution, _) do
    resolution
  end

  def call(resolution, _) do
    if has_not_allowed_fields?(resolution) do
      Resolution.put_result(resolution, {:error, :unauthorized})
    else
      resolution
    end
  end

  # Helper functions

  defp has_not_allowed_fields?(resolution) do
    requested_fields = Utils.requested_fields(resolution)

    Enum.any?(requested_fields, fn field ->
      field not in @allowed_fields_for_anon_users
    end)
  end
end
