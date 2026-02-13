defmodule Sanbase.Entity.Opts do
  @moduledoc ~s"""
  Options transformation logic for entity queries.

  Transforms API params into suitable params for SQL queries. Handles
  user filtering, public/private status, slug-to-id resolution, and
  embedding generation for similarity search.
  """

  @doc """
  Transforms the API params into suitable params for the SQL query.

  At the end the following flags will be added:
  - user_ids -- list of user ids to fetch
  - public_status -- :public | :private | :all -- which entities to fetch
  - can_access_user_private_entities -- If there is access to the private entities
  - filter -- filter by project_ids
  """
  def update_opts(opts) do
    # This will be used in combination with public_status.
    # Only when `currentUserData` is set to true it will allow to fetch
    # private entities of the user. Otherwise it is false by default.
    opts = opts |> Keyword.put_new(:can_access_user_private_entities, false)

    opts =
      case Keyword.get(opts, :user_id_data_only) do
        user_id when is_integer(user_id) ->
          if Keyword.get(opts, :user_ids),
            do:
              raise(
                ArgumentError,
                "Something has unexpectedly set :user_ids in opts while trying to put user_id_data_only"
              )

          opts |> Keyword.put(:user_ids, [user_id])

        _ ->
          opts |> Keyword.delete(:user_ids)
      end

    opts =
      case Keyword.get(opts, :filter) do
        %{public_status: value} when value in [:all, :public, :private] ->
          Keyword.put(opts, :public_status, value)

        %{public_status: value} ->
          raise ArgumentError, "Invalid value for :public_status option: #{inspect(value)}"

        _ ->
          if is_integer(Keyword.get(opts, :current_user_data_only)) do
            # For backwards compatibility, when current_user_data_only is set
            # previously we returned all public and private entities of the user.
            # Now, if the `public_status` is not explicitly set, we do the same.
            Keyword.put(opts, :public_status, :all)
          else
            # If current_user_data_only is provided then we can only fetch public
            # entities. If the public_status is something else and current_user_data_only
            # is not set, the resolver will reject the query and return a descriptive error
            Keyword.put(opts, :public_status, :public)
          end
      end

    opts =
      case Keyword.get(opts, :filter) do
        # Filter only those entities (charts, etc.) which are about these slugs
        %{slugs: slugs} = filter ->
          ids = Sanbase.Project.List.ids_by_slugs(slugs, [])
          filter = Map.put(filter, :project_ids, ids)
          Keyword.put(opts, :filter, filter)

        _ ->
          opts
      end

    opts =
      case Keyword.get(opts, :user_role_data_only) do
        :san_family ->
          if Keyword.get(opts, :user_ids),
            do:
              raise(
                ArgumentError,
                "Something has unexpectedly set :user_ids in opts while setting user_role_data_only"
              )

          user_ids = Sanbase.Accounts.Role.san_family_ids()

          opts
          |> Keyword.put(:user_ids, user_ids)

        :san_team ->
          if Keyword.get(opts, :user_ids),
            do:
              raise(
                ArgumentError,
                "Something has unexpectedly set :user_ids in opts while setting user_role_data_only"
              )

          user_ids = Sanbase.Accounts.Role.san_team_ids()

          opts
          |> Keyword.put(:user_ids, user_ids)

        _ ->
          opts
      end

    opts =
      case Keyword.get(opts, :current_user_data_only) do
        user_id when is_integer(user_id) ->
          if Keyword.get(opts, :user_ids),
            do:
              raise(
                ArgumentError,
                "Something has unexpectedly set :user_ids in opts while setting current_user_data_only"
              )

          opts
          |> Keyword.put(:user_ids, [user_id])
          |> Keyword.put(:can_access_user_private_entities, true)

        _ ->
          opts
      end

    Enum.each([:public_status, :can_access_user_private_entities], fn key ->
      if not Keyword.has_key?(opts, key),
        do: raise(ArgumentError, "Key #{key} missing in the Entity opts")
    end)

    opts
  end

  @doc """
  Adds embedding to opts if not already present.

  If opts has :embedding, returns opts unchanged.
  If it has :ai_search_term, generates the embedding from it.
  Returns {:ok, opts} or {:error, reason}.
  """
  def put_new_embedding_opts(opts) do
    case Keyword.get(opts, :embedding) do
      [_ | _] ->
        {:ok, opts}

      nil ->
        case Keyword.get(opts, :ai_search_term) do
          ai_search_term when is_binary(ai_search_term) ->
            case Sanbase.AI.Embedding.generate_embeddings([ai_search_term], 1536) do
              {:ok, [embedding]} ->
                opts = Keyword.put(opts, :embedding, embedding)
                {:ok, opts}

              {:error, reason} ->
                {:error, "Failed to generate embeddings: #{inspect(reason)}"}
            end

          _ ->
            {:error, "The ai_search_term must be a string"}
        end
    end
  end
end
