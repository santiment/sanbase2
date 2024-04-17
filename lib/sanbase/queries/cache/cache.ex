defmodule Sanbase.Queries.Cache do
  @moduledoc ~s"""
  Holds the last computed result of query.

  The cache is the dynamic part of the dashboard as the result of execution
  of the SQL can change on every run. Dashboards can be slow to compute or
  can be viewed by many users. Because of this, a cached version is kept in
  the database and is shown to the users.
  """
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset
  import Sanbase.Utils.ErrorHandling, only: [changeset_errors_string: 1]

  alias Sanbase.Queries.Query
  alias Sanbase.Accounts.User
  alias Sanbase.Queries.Executor.Result

  @type query_id :: Query.query_id()
  @type user_id :: User.user_id()

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          query_id: query_id(),
          data: map()
        }

  @timestamps_opts [type: :utc_datetime]
  schema "queries_cache" do
    belongs_to(:query, Query)
    belongs_to(:user, User)

    field(:data, :string)

    # When showing the cache, compare this hash to the query
    # hash to determine if the cache is outdated
    field(:query_hash, :string)

    timestamps()
  end

  @doc ~s"""
  Create or update a cache of a query execution.

  Each query has at most one cached version for a user.
  """
  @spec create_or_update_cache(Query.t(), Result.t(), user_id, Keyword.t()) ::
          {:ok, t()} | {:error, String.t()}
  def create_or_update_cache(query, query_result, user_id, opts) do
    with {:ok, compressed_result} <- compress_encode_result(query_result),
         true <- query_result_size_allowed?(compressed_result, opts) do
      Ecto.Multi.new()
      |> Ecto.Multi.run(:get_if_exists, fn _, _ ->
        case get(query.id, user_id) do
          {:ok, cache} -> {:ok, cache}
          _ -> {:ok, nil}
        end
      end)
      |> Ecto.Multi.run(:update_or_create_cache, fn _, %{get_if_exists: cache} ->
        case cache do
          %__MODULE__{} = cache -> update(cache, query, compressed_result, user_id)
          nil -> new(query, compressed_result, user_id)
        end
      end)
      |> Sanbase.Repo.transaction()
      |> case do
        {:ok, result} ->
          {:ok, result}

        {:error, _name, %Ecto.Changeset{} = changeset, _changes_so_far} ->
          {:error, changeset_errors_string(changeset)}

        {:error, _name, error, _changes_so_far} ->
          {:error, error}
      end
    end
  end

  @doc ~s"""
  Fetch the cache record of a given query created by a given user
  """
  @spec get(query_id, user_id) :: {:ok, t()} | {:error, String.t()}
  def get(query_id, user_id, _opts \\ []) do
    query = from(qc in __MODULE__, where: qc.query_id == ^query_id and qc.user_id == ^user_id)
    # Return the cache of the owner of the query, if there is no cache for the current user?
    # Or allow only the query owner to cache it?
    case Sanbase.Repo.one(query) do
      %__MODULE__{} = cache -> {:ok, cache}
      nil -> {:error, "Query cache for query #{query_id} and user #{user_id} does not exist"}
    end
  end

  def compress_encode_result(query_result) do
    result =
      query_result
      |> Map.from_struct()
      |> :erlang.term_to_binary()
      |> :zlib.gzip()
      |> Base.encode64()

    {:ok, result}
  rescue
    e -> {:error, "Failed to compress and encode a query result: #{Exception.message(e)}"}
  end

  # This should not be called without a user and private query.
  def get_cached_executions(query, querying_user_id) do
    with {:ok, query} <- get_cached_executions_query(query, querying_user_id),
         result = Sanbase.Repo.all(query) do
      {:ok, result}
    end
  end

  def decode_decompress_result(result) do
    result
    |> Base.decode64!()
    |> :zlib.gunzip()
    |> :erlang.binary_to_term()
    |> then(&struct!(Result, &1))
    |> then(&maybe_transform_datetimes/1)
  end

  # Private functions

  defp maybe_transform_datetimes(%Result{} = result) do
    result
    |> Map.update!(:query_start_time, &to_datetime/1)
    |> Map.update!(:query_end_time, &to_datetime/1)
  end

  defp to_datetime(dt) when is_binary(dt) do
    Sanbase.DateTimeUtils.from_iso8601!(dt)
  end

  defp to_datetime(dt), do: dt

  defp get_cached_executions_query(%{is_public: true} = query, nil) do
    query =
      from(
        c in __MODULE__,
        # everyone sees the owner's cache
        # querying user see also their own cache
        where: c.query_id == ^query.id and c.user_id == ^query.user_id,
        preload: [:user]
      )

    {:ok, query}
  end

  defp get_cached_executions_query(%{is_public: false}, nil) do
    {:error, "Trying to fetch the cached executions of a private query without being logged in"}
  end

  defp get_cached_executions_query(query, querying_user_id) when is_integer(querying_user_id) do
    query =
      from(
        c in __MODULE__,
        # everyone sees the owner's cache
        # querying user see also their own cache
        where:
          c.query_id == ^query.id and
            (c.user_id == ^query.user_id or c.user_id == ^querying_user_id),
        preload: [:user]
      )

    {:ok, query}
  end

  defp new(%Query{} = query, compressed_result, user_id) do
    %__MODULE__{}
    |> change(%{
      query_id: query.id,
      user_id: user_id,
      query_hash: Query.hash(query),
      data: compressed_result
    })
    |> Sanbase.Repo.insert()
  end

  defp update(%__MODULE__{} = cache, %Query{} = query, compressed_result, _user_id) do
    cache
    |> change(%{query_hash: Query.hash(query), data: compressed_result})
    |> Sanbase.Repo.update()
  end

  # The byte size of the compressed rows should not exceed the allowed limit.
  # Otherwise simple queries like `select * from intraday_metircs limit 9999999`
  # can be executed and fill the database with lots of data.
  @allowed_kb_size 500
  defp query_result_size_allowed?(compressed_result, opts) do
    kb_size = byte_size(compressed_result) / 1024
    kb_size = Float.round(kb_size, 2)

    allowed_kb_size = Keyword.get(opts, :max_query_size_kb_allowed, @allowed_kb_size)

    case kb_size do
      size when size <= allowed_kb_size ->
        true

      size ->
        {:error,
         """
         Cannot cache the query because its compressed is #{size}KB \
         which is over the limit of #{allowed_kb_size}KB
         """}
    end
  end
end
