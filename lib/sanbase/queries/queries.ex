defmodule Sanbase.Queries do
  @moduledoc ~s"""
  Boundary module for Santiment Queries.

  TODO: Add more documentation
  """
  alias Sanbase.Repo
  alias Sanbase.Queries
  alias Sanbase.Queries.Query
  alias Sanbase.Queries.QueryMetadata
  alias Sanbase.Queries.QueryExecution
  alias Sanbase.Dashboards.Dashboard
  alias Sanbase.Dashboards.DashboardQueryMapping
  alias Sanbase.Accounts.User
  alias Sanbase.Clickhouse.Query.Environment

  import Sanbase.Utils.ErrorHandling, only: [changeset_errors_string: 1]

  @compile_env Application.compile_env(:sanbase, :env)

  @type user_id :: non_neg_integer()
  @type query_id :: Query.query_id()
  @type dashboard_id :: Dashboard.dashboard_id()
  @type dashboard_query_mapping_id :: DashboardQueryMapping.dashboard_query_mapping_id()

  @type create_query_args :: %{
          optional(:name) => String.t(),
          optional(:description) => String.t(),
          optional(:is_public) => boolean(),
          optional(:settings) => map(),
          optional(:sql_query_text) => String.t(),
          optional(:sql_query_parameters) => Map.t(),
          optional(:origin_id) => non_neg_integer()
        }

  @type update_query_args :: %{
          optional(:name) => String.t(),
          optional(:description) => String.t(),
          optional(:is_public) => boolean(),
          optional(:settings) => map(),
          optional(:sql_query_text) => String.t(),
          optional(:sql_query_parameters) => Map.t(),
          optional(:origin_id) => non_neg_integer(),
          # updatable by moderators only
          optional(:is_deleted) => boolean(),
          optional(:is_hidden) => boolean()
        }

  @typedoc ~s"""
  Preload options
  """
  @type preload_option :: {:preload?, boolean()} | {:preload, [atom()]}
  @type preload_opts :: [preload_option]

  @typedoc ~s"""
  Pagination options
  """
  @type pagination_option ::
          {:page, non_neg_integer()} | {:page_size, non_neg_integer()}
  @type pagination_opts :: [pagination_option]

  @typedoc ~s"""
  Union of both the pagination and preload opttions
  """
  @type pagination_and_preload_option :: pagination_option | preload_option
  @type pagination_and_preload_opts :: [pagination_and_preload_option]

  @typedoc ~s"""
  Control the storing of the query execution details.
  After a query is executed, an additional query is made in order
  to fetch the execution details (they are not part of the query result).
  """
  @type run_query_option ::
          {:store_execution_details, boolean()}
          | {:wait_fetching_details_ms, non_neg_integer()}

  @type run_query_opts :: [run_query_option]

  @doc ~s"""
  Execute the query and return the result.

  The query is executed synchronously. This means that the function will block
  until the query is executed and the result is returned. The query execution stats
  are computed asynchronously due to the way Clickhouse works -- it buffers in memory
  the execution stats for 7500ms before flushing them to the disk.

  The function accepts 3 arguments:
    - The query that is being executed
    - Query metadata - additional information about the execution - is it executed via the
    web app or via the API, is it coming from production or dev/test environment.
    - user_id is the id of the user that is executing the query.
  """
  @spec run_query(Query.t(), User.t(), QueryMetadata.t(), Keyword.t()) ::
          {:ok, Executor.Result.t()} | {:error, String.t()}
  def run_query(%Query{} = query, user, query_metadata, opts \\ []) do
    query_metadata = Map.put_new(query_metadata, :sanbase_user_id, user.id)

    with {:ok, environment} <- Environment.new(query, user),
         {:ok, result} <- Queries.Executor.run(query, query_metadata, environment) do
      maybe_store_execution_data_async(result, user.id, opts)

      {:ok, result}
    end
  end

  def user_executions_summary(user_id) do
    query = QueryExecution.executions_summary(user_id)

    {:ok, Sanbase.Repo.one(query)}
  end

  @doc ~s"""
  Check if the user has credits left to run a computation.

  Each query has a cost in credits. The cost is computed based on the query
  profiling details - how much RAM memory it used, how much data it read from
  the disk, how big is the result, etc.
  """
  @spec user_can_execute_query(%User{}, String.t(), String.t()) :: :ok | {:error, String.t()}
  def user_can_execute_query(user, product_code, plan_name) do
    Queries.Authorization.user_can_execute_query(user, product_code, plan_name)
  end

  @doc ~s"""
  Get a query in order to read or run it.
  This can be done by owner or by anyone if the query is public.
  """
  @spec get_query(query_id, user_id) :: {:ok, Query.t()} | {:error, String.t()}
  def get_query(query_id, querying_user_id) do
    query = Query.get_for_read(query_id, querying_user_id)

    case Repo.one(query) do
      %Query{} = query -> {:ok, query}
      nil -> {:error, "Query does not exist or you don't have access to it."}
    end
  end

  @doc ~s"""
  Get a query in the context of a dashboard in order to read or run it.

  The query is identified by the dashboard_query_mapping_id. This can be
  done by owner or by anyone if the dashboard is public.
  """
  @spec get_dashboard_query(dashboard_id, dashboard_query_mapping_id, user_id) ::
          {:ok, Query.t()} | {:error, String.t()}
  def get_dashboard_query(dashboard_id, mapping_id, querying_user_id) do
    query = DashboardQueryMapping.by_id(mapping_id)

    with %DashboardQueryMapping{dashboard: dashboard, query: query} <- Repo.one(query),
         %Dashboard{id: ^dashboard_id} <- dashboard,
         true <- dashboard.is_public or dashboard.user_id == querying_user_id,
         {:ok, query} <- Sanbase.Dashboards.apply_global_parameters(query, dashboard, mapping_id) do
      {:ok, query}
    else
      _ ->
        {:error,
         """
         Dashboard query mapping with id #{mapping_id} does not exist,
         it is not part of dashboard #{dashboard_id}, or the dashboard is not public.
         """}
    end
  end

  @doc ~s"""
  Construct a in-memory query struct representing a query that is not persisted
  in the database. This is used for ephemeral queries that are provided directly
  to the API as a string and a map of parameters.
  """
  @spec get_ephemeral_query_struct(String.t(), Map.t(), User.t()) :: Query.t()
  def get_ephemeral_query_struct(sql_query_text, sql_query_parameters, user) do
    %Query{
      sql_query_text: sql_query_text,
      sql_query_parameters: sql_query_parameters,
      user_id: user.id,
      user: user
    }
  end

  @doc ~s"""
  Get a list of queries that belong to a user ordered by last updated.
  The owner of the queries can see all of them, but other users can only see
  public queries.

  `opts` can contain:
    - `:page` and `:page_size` keys to control the pagination;
    - `:preload?` and `:preload` keys to control the preloads.
  """
  @spec get_user_queries(query_id, user_id, pagination_and_preload_opts) :: {:ok, [Query.t()]}
  def get_user_queries(user_id, querying_user_id, opts) do
    query = Query.get_user_queries(user_id, querying_user_id, opts)

    {:ok, Repo.all(query)}
  end

  @doc ~s"""
  Get a list of public queries.

  `opts` can contain:
    - `:page` and `:page_size` keys to control the pagination;
    - `:preload?` and `:preload` keys to control the preloads.
  """
  @spec get_public_queries(pagination_and_preload_opts()) :: {:ok, [Query.t()]}
  def get_public_queries(opts) do
    query = Query.get_public_queries(opts)

    {:ok, Repo.all(query)}
  end

  @doc ~s"""
  Return a list of the executed queries for a user.
  The options' list can contain `:page` and `:page_size` keys
  to control the pagination.

  This function presumes that the user themself are fetching the list
  of query executions.

  `opts` can contain:
    - `:page` and `:page_size` keys to control the pagination;
    - `:preload?` and `:preload` keys to control the preloads.
  """
  @spec get_query(user_id, pagination_and_preload_opts()) :: {:ok, [QueryExecution.t()]}
  def get_user_query_executions(user_id, opts) do
    query = QueryExecution.get_user_query_executions(user_id, opts)

    {:ok, Repo.all(query)}
  end

  def get_query_execution(clickhouse_query_id, querying_user_id) do
    query =
      QueryExecution.get_query_execution_by_clickhouse_query_id(
        clickhouse_query_id,
        querying_user_id
      )

    case Repo.one(query) do
      %QueryExecution{} = execution -> {:ok, execution}
      nil -> {:error, "Query execution does not exist, or it is owned by another user"}
    end
  end

  @doc ~s"""
  Create a new query.

  When creating a query, the following parameters can be provided:
  - name: The name of the query
  - description: The description of the query
  - is_public: Whether the query is public or not
  - settings: The settings of the query. This is an arbitrary map (JSON object)
  - sql_query_text: The SQL query itself
  - sql_query_parameters: The parameters of the SQL query.
  - origin_id: The id of the original query if this query is a duplicate of another query.
    This is used to track changes.
  - user_id: The id of the user that created the query.

  The SQL query must be valid Clickhouse SQL. It can access only some of the tables in the database.
  The system tables are not accessible.

  Parametrization of the query is done via templating - the places that need to be filled
  are indicated by the syntax {{<key>}}. Example: WHERE address = {{address}}
  The parameters are provided as a map in the `sql_query_parameters` parameter.
  """
  @spec create_query(create_query_args(), user_id) ::
          {:ok, Query.t()} | {:error, String.t()} | {:error, Ecto.Changeset.t()}
  def create_query(args, user_id) do
    uuid = "query_" <> Uniq.UUID.uuid7()
    args = args |> Map.merge(%{user_id: user_id, uuid: uuid})

    changeset = Query.create_changeset(%Query{}, args)

    case Repo.insert(changeset) do
      {:ok, %Query{} = query} ->
        query = query |> Repo.preload([:user])
        {:ok, query}

      {:error, changeset} ->
        {:error, changeset_errors_string(changeset)}
    end
  end

  @doc ~s"""
  Update a query.
  Updating can be done only by the owner of the query.

  Check the create_query/2 documentation for description of the parameters.
  By updating the query **cannot** change:
  - user_id - The query ownership cannot be changed/
  In addition, updating the query can change:
  - is_hidden - Hide the query from the getMost* APIs (getMostRecent, getMostUsed, getMostRecent)
  - is_deleted - Soft-delete the query by setting a flag in the table. The actual record
    is not deleted. This is done by moderators when some inappropriate content is shown on
    a public page.
  """
  @spec update_query(query_id, update_query_args(), user_id) ::
          {:ok, Query.t()} | {:error, String.t()} | {:error, Ecto.Changeset.t()}
  def update_query(query_id, attrs, querying_user_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_for_mutation, fn _repo, _changes ->
      get_for_mutation(query_id, querying_user_id)
    end)
    |> Ecto.Multi.run(:update, fn _repo, %{get_for_mutation: struct} ->
      Query.update_changeset(struct, attrs) |> Repo.update()
    end)
    |> Repo.transaction()
    |> process_transaction_result(:update)
  end

  @doc ~s"""
  Delete a query.
  Deleting can be done only by the owner of the query.
  """
  @spec delete_query(query_id, user_id) ::
          {:ok, Query.t()} | {:error, String.t()}
  def delete_query(query_id, querying_user_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_for_mutation, fn _repo, _changes ->
      get_for_mutation(query_id, querying_user_id)
    end)
    |> Ecto.Multi.run(:delete, fn _repo, %{get_for_mutation: struct} ->
      Repo.delete(struct)
    end)
    |> Repo.transaction()
    |> process_transaction_result(:delete)
  end

  # Private functions

  defp get_store_execution_opts(opts) do
    # In test env allow the configuration to be provided as application env
    # so that we can disable the storing of details even when the function is called through
    # the API where  we cannot provide the opts arg.
    case @compile_env do
      :test ->
        [
          store_execution_details:
            Application.get_env(
              :__sanbase_queries__,
              :__store_execution_details__,
              Keyword.get(opts, :store_execution_details, true)
            ),
          wait_fetching_details_ms:
            Application.get_env(
              :__sanbase_queries__,
              :__wait_fetching_details_ms_,
              Keyword.get(opts, :wait_fetching_details_ms, 7500)
            )
        ]

      _ ->
        [
          store_execution_details: Keyword.get(opts, :store_execution_details, true),
          wait_fetching_details_ms: Keyword.get(opts, :wait_fetching_details_ms, 7500)
        ]
    end
  end

  defp maybe_store_execution_data_async(result, user_id, opts) do
    # When a Clickhouse query is executed, the query details are buffered in
    # memory for up to 7500ms before they flush to the database table.
    # Because of this, storing the execution data is done in a separate process
    # to avoid blocking the main process and to return the result to the user
    # faster.
    opts = get_store_execution_opts(opts)

    if opts[:store_execution_details] do
      store = fn ->
        QueryExecution.store_execution(result, user_id, opts[:wait_fetching_details_ms])
      end

      # In test do not do it in an async way as this can lead to mocking issues.
      # It also helps find issues where neither store_execution_details is set to false
      # nor wait_fetching_details_ms is set to 0.
      case @compile_env do
        :test ->
          store.()

        _ ->
          spawn(fn -> store.() end)
          # _ -> Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn -> store.() end)
      end
    end
  end

  @doc ~s"""
  Cache a query execution
  TODO: Add more documentation
  """
  @spec cache_query_execution(query_id, any(), user_id) :: any()
  def cache_query_execution(
        query_id,
        query_result,
        user_id
      ) do
    Queries.Cache.create_or_update_cache(
      query_id,
      query_result,
      user_id
    )
  end

  # Private functions

  defp get_for_mutation(query_id, querying_user_id) do
    query = Query.get_for_mutation(query_id, querying_user_id)

    case Repo.one(query) do
      %Query{} = struct -> {:ok, struct}
      nil -> {:error, "Query does not exist or it belongs to another user."}
    end
  end

  defp process_transaction_result({:ok, map}, ok_field),
    do: {:ok, map[ok_field]}

  defp process_transaction_result({:error, _, %Ecto.Changeset{} = changeset, _}, _ok_field),
    do: {:error, changeset_errors_string(changeset)}

  defp process_transaction_result({:error, _, error, _}, _ok_field),
    do: {:error, error}
end
