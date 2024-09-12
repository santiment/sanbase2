defmodule Sanbase.Dashboards.DashboardCache do
  @moduledoc ~s"""
  Holds the last computed result of dashboard's queries.

  The cache is the dynamic part of the dashboard as the result of execution
  of the SQL can change on every run. Dashboards can be slow to compute or
  can be viewed by many users. Because of this, a cached version is kept in
  the database and is shown to the users.
  """
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset
  import Sanbase.Utils.Transform, only: [maybe_apply_function: 2]
  import Sanbase.Utils.ErrorHandling, only: [changeset_errors_string: 1]

  alias Sanbase.Repo
  alias Sanbase.Dashboards.Dashboard
  alias Sanbase.Queries.Executor.Result
  alias Sanbase.Queries.QueryCache

  @type user_id :: Sanbase.Accounts.User.user_id()
  @type dashboard_id :: Dashboard.dashboard_id()
  @type parameters_override :: map()
  @type dashboard_query_mapping_id :: Dashboard.dashboard_query_mapping_id()

  @type query_cache :: %{
          dashboard_query_mapping_id => map()
        }

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          dashboard_id: dashboard_id(),
          queries: %{
            # the key is dashboard_query_mapping_id
            optional(String.t()) => query_cache()
          }
        }

  schema "dashboards_cache" do
    field(:dashboard_id, :integer)
    field(:parameters_override_hash, :string, default: "none")
    field(:queries, :map, default: %{})

    timestamps()
  end

  # defp get_for_read(dashboard_id, querying_user_id) do
  # end

  # def get_for_mutation(dashboard_id, querying_user_id) do
  #   from(dc in __MODULE__,
  #     where: dc.dashboard_id == ^dashboard_id,
  #     join: d in Dashboard,
  #     on: dc.dashboard_id == d.id
  #   )
  # end

  @doc ~s"""
  Hash the parameters map to a string.
  The hash will be stored in the database.
  """
  @spec hash_parameters(map()) :: String.t()
  def hash_parameters(%{} = params) when map_size(params) == 0, do: "none"

  def hash_parameters(%{} = params) do
    binary = :erlang.term_to_binary(params)

    # Base64 encodes 6 bits of information per character, so 16 characters is 96 bits
    # 1.3x10^13 attempts are needed (13 trillion) to have 0.1% chance of collisions
    :crypto.hash(:sha256, binary)
    |> Base.encode64(padding: false)
    |> :erlang.binary_part(0, 16)
  end

  @doc ~s"""
  Fetch the latest cache values for the given dashboard.

  The second `opts` argument can contain the following options:
  - lock_for_update - Set to true, if the record is fetched for an update
  - transform_loaded_queries - If set to true, the loaded query caches are
  transformed from having `compressed_rows` to `rows`. Defaults to true.
  """

  # def by_dashboard_id(dashboard_id, querying_user_id, opts) do
  #   Ecto.Multi.new()
  #   |> Ecto.Multi.run(:get_dashboard_cache, fn _ ->
  #     get_for_read(dashboard_id, querying_user_id)
  #   end)
  # end

  @spec by_dashboard_id(dashboard_id, parameters_override, user_id, Keyword.t()) ::
          {:ok, t()} | {:error, String.t()}
  def by_dashboard_id(dashboard_id, parameters_override, querying_user_id, opts \\ []) do
    hash = hash_parameters(parameters_override)

    query =
      from(d in __MODULE__,
        where: d.dashboard_id == ^dashboard_id and d.parameters_override_hash == ^hash
      )

    query =
      case Keyword.get(opts, :lock_for_update, false) do
        false -> query
        true -> query |> lock("FOR UPDATE")
      end

    case Repo.one(query) do
      nil -> new(dashboard_id, parameters_override, querying_user_id)
      %__MODULE__{} = cache -> {:ok, cache}
    end
    |> maybe_apply_function(&transform_loaded_dashboard_cache(&1, opts))
  end

  @doc ~s"""
  Get the latest query cache for the given dashboard and dashboard_query_mapping_id.

  The second `opts` argument can contain the following options:
  - transform_loaded_queries - If set to true, the loaded query caches are
  transformed from having `compressed_rows` to `rows`. Defaults to true.
  """
  @spec by_dashboard_and_dashboard_query_mapping_id(
          dashboard_id(),
          dashboard_query_mapping_id(),
          Keyword.t()
        ) :: {:ok, query_cache()} | {:error, String.t()}
  def by_dashboard_and_dashboard_query_mapping_id(
        dashboard_id,
        dashboard_query_mapping_id,
        opts \\ []
      ) do
    query = """
    SELECT t.query
    FROM dashboards_cache cache
    CROSS JOIN LATERAL (
      SELECT value AS query
      FROM jsonb_each(cache.queries) AS x(key, value)
      WHERE cache.dashboard_id = $1 AND key = $2
    ) AS t
    """

    params = [dashboard_id, dashboard_query_mapping_id]

    case Repo.query(query, params) do
      {:ok, %{rows: [[%{} = query_cache]]}} -> {:ok, query_cache}
      _ -> {:error, "Cannot load dashboard query cache"}
    end
    |> maybe_apply_function(&transform_loaded_dashboard_cache(&1, opts))
  end

  @doc ~s"""
  Create a new empty record for the given dashboard_id.
  """
  @spec new(dashboard_id, parameters_override, user_id) :: {:ok, t()} | {:error, any()}
  def new(dashboard_id, parameters_override, querying_user_id) do
    hash = hash_parameters(parameters_override)

    case Sanbase.Dashboards.get_visibility_data(dashboard_id) do
      {:ok, %{user_id: user_id, is_public: is_public}}
      when user_id == querying_user_id or is_public == true ->
        %__MODULE__{}
        |> change(%{
          dashboard_id: dashboard_id,
          parameters_override_hash: hash
        })
        |> Repo.insert()
        |> maybe_transform_error()

      _ ->
        {:error,
         "Dashboard with id #{dashboard_id} does not exist or the dashboard is private and the user with id #{querying_user_id} is not the owner of it."}
    end
  end

  @doc ~s"""
  Update the dashboard's query cache with the provided result.
  """
  @spec update_query_cache(
          dashboard_id(),
          parameters_override,
          dashboard_query_mapping_id,
          Result.t(),
          user_id,
          Keyword.t()
        ) ::
          {:ok, t()} | {:error, any()}
  def update_query_cache(
        dashboard_id,
        parameters_override,
        dashboard_query_mapping_id,
        query_result,
        user_id,
        opts
      ) do
    query_cache =
      QueryCache.from_query_result(query_result, dashboard_query_mapping_id, dashboard_id)

    # Do not transform the loaded queries cache. Transforming it would
    # convert `compressed_rows` to `rows`, which will be written back and break
    with true <- query_result_size_allowed?(query_cache),
         {:ok, cache} <-
           by_dashboard_id(dashboard_id, parameters_override, user_id,
             transform_loaded_queries: false,
             lock_for_update: true
           ) do
      query_cache = query_cache |> Map.from_struct() |> Map.delete(:rows)

      queries =
        Map.update(cache.queries, dashboard_query_mapping_id, query_cache, fn _ -> query_cache end)

      cache
      |> change(%{queries: queries})
      |> Repo.update()
      |> maybe_transform_error()
      |> maybe_apply_function(&transform_loaded_dashboard_cache(&1, opts))
    end
  end

  @doc ~s"""
  Remove the query result from the cache. This is invoked when the panel is
  removed from the dashboard.
  """
  @spec remove_query_cache(dashboard_id(), dashboard_query_mapping_id(), user_id) ::
          {:ok, t()} | {:error, any()}
  def remove_query_cache(dashboard_id, dashboard_query_mapping_id, querying_user_id) do
    {:ok, cache} = by_dashboard_id(dashboard_id, querying_user_id, lock_for_update: true)
    queries = Enum.reject(cache.queries, &(&1.id == dashboard_query_mapping_id))

    cache
    |> change(%{queries: queries})
    |> Repo.update()
    |> maybe_transform_error()
  end

  # Private functions

  defp transform_loaded_dashboard_cache(%__MODULE__{} = cache, opts) do
    flag = Keyword.get(opts, :transform_loaded_queries, true)

    queries =
      cache.queries
      |> Map.new(fn {dashboard_query_mapping_id, query_cache} ->
        query_cache =
          case flag do
            true -> transform_loaded_queries(query_cache)
            false -> query_cache
          end

        {dashboard_query_mapping_id, query_cache}
      end)

    %{cache | queries: queries}
  end

  defp transform_loaded_queries(query_cache) do
    query_cache = atomize_keys(query_cache)

    %{compressed_rows: compressed_rows, updated_at: updated_at} = query_cache
    %{query_start_time: start_dt, query_end_time: query_end_dt} = query_cache

    {:ok, rows} =
      compressed_rows
      |> Result.decompress_rows()
      |> transform_rows()

    updated_at = to_datetime(updated_at)

    query_cache
    |> Map.drop([:compressed_rows, :updated_at, :query_start_time, :query_end_time])
    |> Map.merge(%{
      rows: rows,
      updated_at: updated_at,
      id: query_cache["id"],
      query_start_time: Sanbase.DateTimeUtils.from_iso8601!(start_dt),
      query_end_time: Sanbase.DateTimeUtils.from_iso8601!(query_end_dt)
    })
  end

  defp to_datetime(data) do
    case data do
      %DateTime{} ->
        data

      <<_::binary>> ->
        {:ok, dt, _} = DateTime.from_iso8601(data)
        dt
    end
  end

  defp atomize_keys(map) do
    map
    |> Map.new(fn
      {k, v} when is_atom(k) ->
        {k, v}

      {k, v} when is_binary(k) ->
        # Ignore old, no longer existing keys like san_query_id
        try do
          {String.to_existing_atom(k), v}
        rescue
          _ -> {nil, nil}
        end
    end)
    |> Map.delete(nil)
  end

  defp transform_rows(rows) do
    transformed_rows =
      rows
      |> Enum.map(fn row ->
        row
        |> Enum.map(fn
          elem when is_binary(elem) ->
            case DateTime.from_iso8601(elem) do
              {:ok, datetime, _} -> datetime
              _ -> elem
            end

          elem ->
            elem
        end)
      end)

    {:ok, transformed_rows}
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
         Cannot cache the panel because its compressed size is #{size}KB \
         which is over the limit of #{@allowed_kb_size}KB
         """}
    end
  end

  defp maybe_transform_error({:ok, _} = result), do: result

  defp maybe_transform_error({:error, changeset}),
    do: {:error, changeset_errors_string(changeset)}
end
