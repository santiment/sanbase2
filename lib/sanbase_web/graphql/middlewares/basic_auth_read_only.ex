defmodule SanbaseWeb.Graphql.Middlewares.BasicAuthReadOnly do
  @moduledoc ~s"""
  Restricts basic auth requests to reading public data.

  A basic auth request authenticates as a fake superuser (`%User{id: -1}`) with full
  metric access. That is fine for reading public data, but the same identity must not
  change anything or see anything private. This middleware is prepended, at schema build
  time via `SanbaseWeb.Graphql.Schema.middleware/3`, to every field that a basic auth
  request must not resolve:

    - every mutation;
    - every field that requires a user identity (`UserAuth`, `JWTAuth`,
      `JWTModeratorAuth`). These are scoped to "the current user", which for basic auth
      is the fake user -1. The system user is also -1, so for example the SQL query
      executions run on behalf of AI chat users are stored under that id;
    - every field gated only by `BasicAuth`. These expose internal data about users;
    - the root fields listed in `@denied_query_fields`, which return the fake user
      itself and give access to the data owned by user -1.

  Requests that do not use basic auth pass through untouched.
  """
  @behaviour Absinthe.Middleware

  alias Absinthe.Resolution

  alias SanbaseWeb.Graphql.Middlewares.{
    BasicAuth,
    JWTAuth,
    JWTModeratorAuth,
    UserAuth
  }

  @identity_middlewares [BasicAuth, JWTAuth, JWTModeratorAuth, UserAuth]
  @denied_query_fields [:current_user]

  @error_msg "Basic authentication has read-only access to public data. This field is not available with basic authentication."

  @impl true
  def call(%Resolution{context: %{auth: %{auth_method: :basic}}} = resolution, _opts) do
    # Absinthe keeps calling the remaining middleware after `put_result/2`, and the
    # auth middlewares would overwrite this error. Nothing after this must run.
    %Resolution{} = resolution = Resolution.put_result(resolution, {:error, @error_msg})
    %{resolution | middleware: []}
  end

  def call(%Resolution{} = resolution, _opts), do: resolution

  @doc ~s"""
  Prepend this middleware to the field's middleware if a basic auth request must not
  resolve the field. Called by `SanbaseWeb.Graphql.Schema.middleware/3`.
  """
  @spec maybe_prepend(list(), Absinthe.Type.Field.t(), Absinthe.Type.Object.t()) :: list()
  def maybe_prepend(middleware, field, object) do
    case restricted_field?(middleware, field, object) do
      true -> [{__MODULE__, []} | middleware]
      false -> middleware
    end
  end

  @doc false
  def error_msg(), do: @error_msg

  defp restricted_field?(_middleware, _field, %{identifier: :mutation}), do: true

  defp restricted_field?(_middleware, %{identifier: field}, %{identifier: :query})
       when field in @denied_query_fields,
       do: true

  defp restricted_field?(middleware, _field, _object) do
    Enum.any?(middleware, &identity_middleware?/1)
  end

  defp identity_middleware?({{module, _fun}, _opts}), do: module in @identity_middlewares

  defp identity_middleware?({module, _opts}) when is_atom(module),
    do: identity_middleware?(module)

  defp identity_middleware?(module) when is_atom(module), do: module in @identity_middlewares
  defp identity_middleware?(_), do: false
end
