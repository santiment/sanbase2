defmodule SanbaseWeb.Graphql.Helpers.UserPublicIdHelper do
  @moduledoc """
  Shared helper for resolving user identity from either integer user_id
  or UUID user_public_id arguments in GraphQL resolvers.

  During the transition period both argument styles are supported.
  """

  alias Sanbase.Accounts.User

  @doc """
  Resolve an integer user_id from args that may contain either
  `user_id` (integer) or `user_public_id` (UUID string).

  Custom key names can be passed for endpoints that use different
  arg names (e.g. `secondary_user_id` / `secondary_user_public_id`).

  Returns `{:ok, integer_id}` or `{:error, message}`.
  """
  def resolve_user_id(args, id_key \\ :user_id, public_id_key \\ :user_public_id) do
    id = Map.get(args, id_key)
    public_id = Map.get(args, public_id_key)

    case {id, public_id} do
      {nil, nil} ->
        {:error, "Provide either #{id_key} or #{public_id_key}"}

      {id, nil} ->
        {:ok, Sanbase.Math.to_integer(id)}

      {nil, public_id} ->
        case User.by_public_id(public_id) do
          {:ok, user} -> {:ok, user.id}
          {:error, _} = error -> error
        end

      {_, _} ->
        {:error, "Provide only one of #{id_key} or #{public_id_key}, not both"}
    end
  end

  @doc """
  Same as `resolve_user_id/3` but for optional user_id arguments.
  Returns `{:ok, integer_id}` when either arg is provided,
  or `{:ok, nil}` when neither is provided.
  """
  def resolve_optional_user_id(args, id_key \\ :user_id, public_id_key \\ :user_public_id) do
    id = Map.get(args, id_key)
    public_id = Map.get(args, public_id_key)

    case {id, public_id} do
      {nil, nil} ->
        {:ok, nil}

      {_, _} ->
        resolve_user_id(args, id_key, public_id_key)
    end
  end
end
