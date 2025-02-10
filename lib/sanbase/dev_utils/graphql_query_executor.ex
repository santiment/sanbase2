defmodule Sanbase.DevUtils.GraphQLQueryExecutor do
  @moduledoc """
  A helper module for executing GraphQL queries in elixir shell and livebooks.
  """
  import Plug.Test

  alias Sanbase.Accounts.User
  alias SanbaseWeb.Graphql.AuthPlug
  alias SanbaseWeb.Graphql.ContextPlug

  require SanbaseWeb.Guardian

  @doc """
  Executes a GraphQL query with the given user credentials and returns the result.
  """
  def execute_query(query, current_user \\ nil, opts \\ []) do
    opts = List.wrap(opts)

    opts =
      case current_user do
        nil ->
          opts

        %User{} = current_user ->
          conn = setup_jwt_auth(current_user)
          context = conn.private.absinthe.context

          Keyword.put(opts, :context, context)
      end

    case Absinthe.run(query, SanbaseWeb.Graphql.Schema, opts) do
      {:ok, result} ->
        {:ok, result}

      {:error, errors} ->
        {:error, errors}
    end
  end

  defp setup_jwt_auth(user) do
    conn = Plug.Test.conn("GET", "/")
    device_data = SanbaseWeb.Guardian.device_data(conn)

    {:ok, tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user, device_data)

    conn
    |> init_test_session(tokens)
    |> AuthPlug.call(%{})
    |> ContextPlug.call(%{})
  end
end
