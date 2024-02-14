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

  alias Sanbase.Repo
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

  def get(query_id, user_id) do
    query = from(qc in __MODULE__, where: qc.query_id == ^query_id and qc.user_id == ^user_id)
    # Return the cache of the owner of the query, if there is no cache for the current user?
    # Or allow only the query owner to cache it?
    case Repo.one(query) do
      nil -> {:error, "Query"}
    end
  end

  @doc ~s"""
  Create a new empty record for the given query, result and user.
  """
  @spec new(Query.t(), String.t(), user_id) :: {:ok, t()} | {:error, any()}
  def new(query, compressed_and_encoded_result, user_id) do
    # Only to make sure that the provided JSON is ok to be stored
    with {:ok, result_string} <- Result.decode_and_decompress(compressed_and_encoded_result),
         {:ok, %Result{} = result} <- Result.from_json_string(result_string),
         true <- query_result_size_allowed?(result) do
      hash = Query.hash(query)

      %__MODULE__{}
      |> change(%{query_id: query.id, user_id: user_id, query_hash: hash, data: result})
      |> Repo.insert()
    end
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
