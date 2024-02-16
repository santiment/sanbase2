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
  import Sanbase.Utils.Transform, only: [maybe_apply_function: 2]

  alias Sanbase.Queries
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

  schema "queries_cache" do
    belongs_to(:query, Query)
    belongs_to(:user, User)

    field(:data, :map)

    # When showing the cache, compare this hash to the query
    # hash to determine if the cache is outdated
    field(:query_hash, :string)

    timestamps()
  end

  def create_or_update_cache(query_id, compressed_and_encoded_result, user_id) do
    with {:ok, query} <- Queries.get_query(query_id, user_id),
         {:ok, result_string} <- Result.decode_and_decompress(compressed_and_encoded_result),
         {:ok, %Result{} = result} <- Result.from_json_string(result_string),
         true <- query_result_size_allowed?(result) do
      case get(query_id, user_id) do
        {:ok, cache} -> update(cache, query, compressed_and_encoded_result, user_id)
        {:error, _} -> new(query, compressed_and_encoded_result, user_id)
      end
    end
  end

  @doc ~s"""

  """
  def get(query_id, user_id) do
    query = from(qc in __MODULE__, where: qc.query_id == ^query_id and qc.user_id == ^user_id)
    # Return the cache of the owner of the query, if there is no cache for the current user?
    # Or allow only the query owner to cache it?
    case Sanbase.Repo.one(query) do
      %__MODULE__{} = cache -> {:ok, cache}
      nil -> {:error, "Query"}
    end
  end

  defp new(%Query{} = query, compressed_and_encoded_result, user_id) do
    # Reaching here it is assumed that the result is validated and the user
    # has access to the query
    %__MODULE__{}
    |> change(%{
      query_id: query.id,
      user_id: user_id,
      query_hash: Query.hash(query),
      data: compressed_and_encoded_result
    })
    |> Sanbase.Repo.insert()
  end

  defp update(%__MODULE__{} = cache, %Query{} = query, compressed_and_encoded_result, user_id) do
    # Reaching here it is assumed that the result is validated and the user
    # has access to the query
    cache
    |> change(%{query_hash: Query.hash(query), data: compressed_and_encoded_result})
    |> Sanbase.Repo.update()
  end

  # The byte size of the compressed rows should not exceed the allowed limit.
  # Otherwise simple queries like `select * from intraday_metircs limit 9999999`
  # can be executed and fill the database with lots of data.
  @allowed_kb_size 500
  defp query_result_size_allowed?(query_result) do
    kb_size = byte_size(query_result.compressed_rows) / 1024
    kb_size = Float.round(kb_size, 2)

    case kb_size do
      size when size <= @allowed_kb_size ->
        true

      size ->
        {:error,
         """
         Cannot cache the query because the compressed size of the rows is #{size}KB \
         which is over the limit of #{@allowed_kb_size}KB
         """}
    end
  end
end
