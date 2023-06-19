defmodule Sanbase.Queries do
  @moduledoc ~s"""
  Boundary module for Santiment Queries.

  TODO: Add more documentation
  """
  alias Sanbase.Repo
  alias Sanbase.Queries.Query
  alias Sanbase.Queries.Dashboard
  alias Sanbase.Queries.QueryMetadata
  alias Sanbase.Queries.QueryExecution
  alias Sanbase.Queries.DashboardQueryMapping

  import Sanbase.Utils.ErrorHandling, only: [changeset_errors_string: 1]

  @type user_id :: non_neg_integer()
  @type query_id :: Query.query_id()
  @type dashboard_id :: Dashboard.dashboard_id()
  @type dashboard_query_mapping_id :: DashboardQueryMapping.dashboard_query_mapping_id()

  # TODO: Make part of subscription plan
  @credits_per_month 1_000_000

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
  @spec run_query(Query.t(), QueryMetadata.t(), user_id) ::
          {:ok, Executor.Result.t()} | {:error, String.t()}
  def run_query(%Query{} = query, %{} = query_metadata, user_id) do
    with {:ok, result} <- Sanbase.Queries.Executor.run(query, query_metadata) do
      store_execution_data_async(result, user_id)
      {:ok, result}
    end
  end

  @doc ~s"""
  Check if the user has credits left to run a computation.

  Each query has a cost in credits. The cost is computed based on the query
  profiling details - how much RAM memory it used, how much data it read from
  the disk, how big is the result, etc.
  """
  @spec user_can_execute_query(user_id) :: :ok | {:error, String.t()}
  def user_can_execute_query(user_id) do
    now = DateTime.utc_now()
    beginning_of_month = Timex.beginning_of_month(now)

    query = QueryExecution.credits_spent(user_id, now, beginning_of_month)

    case Sanbase.Repo.one(query) do
      nil -> :ok
      credits_spent when credits_spent < @credits_per_month -> :ok
      _ -> {:error, "The user with id #{user_id} has no credits left"}
    end
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
  def get_dashboard_query(dashboard_id, dashboard_query_mapping_id, querying_user_id) do
    query = DashboardQueryMapping.by_id(dashboard_query_mapping_id)

    with %DashboardQueryMapping{dashboard: dashboard, query: query} <- Repo.one(query),
         %Dashboard{id: ^dashboard_id} <- dashboard,
         true <- dashboard.is_public or dashboard.user_id == querying_user_id,
         {:ok, query} <- resolve_parameters(query, dashboard, dashboard_query_mapping_id) do
      {:ok, query}
    else
      _ ->
        {:error,
         """
         Dashboard query mapping with id #{dashboard_query_mapping_id} does not exist,
         it is not part of dashboard #{dashboard_id}, or the dashboard is not public.
         """}
    end
  end

  @doc ~s"""
  Construct a in-memory query struct representing a query that is not persisted
  in the database. This is used for ephemeral queries that are provided directly
  to the API as a string and a map of parameters.
  """
  @spec get_ephemeral_query_struct(String.t(), Map.t()) :: Query.t()
  def get_ephemeral_query_struct(query, parameters) do
    %Query{
      sql_query: query,
      sql_parameters: parameters
    }
  end

  @doc ~s"""
  Get a list of queries that belong to a user ordered by last updated.
  The owner of the queries can see all of them, but other users can only see
  public queries.
  """
  @spec get_user_queries(query_id, user_id, Keyword.t()) :: {:ok, [Query.t()]}
  def get_user_queries(user_id, querying_user_id, opts) do
    query = Query.get_user_queries(user_id, querying_user_id, opts)

    {:ok, Repo.all(query)}
  end

  @doc ~s"""
  Get a list of public queries.
  """
  @spec get_public_queries(Keyword.t()) :: {:ok, [Query.t()]}
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
  """
  @spec get_query(user_id, Keyword.t()) :: {:ok, [QueryExecution.t()]}
  def get_user_query_executions(user_id, opts) do
    query = QueryExecution.get_user_query_executions(user_id, opts)

    {:ok, Repo.all(query)}
  end

  @doc ~s"""
  Create a new query.

  When creating a query, the following parameters can be provided:
  - name: The name of the query
  - description: The description of the query
  - is_public: Whether the query is public or not
  - settings: The settings of the query. This is an arbitrary map (JSON object)
  - sql_query: The SQL query itself
  - sql_parameters: The parameters of the SQL query.
  - origin_id: The id of the original query if this query is a duplicate of another query.
    This is used to track changes.
  - user_id: The id of the user that created the query.

  The SQL query must be valid Clickhouse SQL. It can access only some of the tables in the database.
  The system tables are not accessible.

  Parametrization of the query is done via templating - the places that need to be filled
  are indicated by the syntax {{<key>}}. Example: WHERE address = {{address}}
  The parameters are provided as a map in the `sql_parameters` parameter.
  """
  @spec create_query(Query.create_query_args(), user_id) ::
          {:ok, Query.t()} | {:error, String.t()} | {:error, Ecto.Changeset.t()}
  def create_query(args, user_id) do
    uuid = "query_" <> Uniq.UUID.uuid7()
    args = args |> Map.merge(%{user_id: user_id, uuid: uuid})

    changeset = Query.create_changeset(%Query{}, args)

    Repo.insert(changeset)
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
  @spec update_query(query_id, Query.create_query_args(), user_id) ::
          {:ok, Query.t()} | {:error, String.t()} | {:error, Ecto.Changeset.t()}
  def update_query(query_id, querying_user_id, attrs) do
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

  @doc ~s"""
  Replace local parameters with the correct global parameter overrides.

  The global parameters are defined on the dashboard level and have the following
  structure:
  %{
    "slug" => %{
      "value" => "bitcoin",
      "overrides" => [%{"dashboard_query_mapping_id" => 101, "parameter" => "slug"}]
    }
  }

  When a query `q` added to the dashboard, with dashboard-query mapping id `dq_id`,
  is executed, the parameters are resolved in the following way:
  - Iterate over the global parameters;
  - Find those who have `dq_id` in their overrides;
  - Extract the key-value pairs from the overrides;
  - Replace the paramters in `q` with the overrides.
  """
  @spec resolve_parameters(Query.t(), Dashboard.t(), non_neg_integer()) ::
          {:ok, Query.t()}
  def resolve_parameters(%Query{} = query, %Dashboard{} = dashboard, query_mapping_id) do
    # Walk over the dashboard global parameters and extract a map, where the keys
    # are parameters of the query and the values are the global values that will
    # override the query values (like %{"slug" => "global_slug_value"}).
    # The name of the global parameter is not needed, only the value and the list
    # of overrides.
    overrides =
      dashboard.parameters
      |> Enum.reduce(
        %{},
        fn {_key, %{"value" => value, "overrides" => overrides}}, acc ->
          case get_query_param_from_overrides(overrides, query_mapping_id) do
            nil -> acc
            %{"parameter" => parameter} -> Map.put(acc, parameter, value)
          end
        end
      )

    new_query_sql_parameters = Map.merge(query.sql_parameters, overrides)

    query = %Query{query | sql_parameters: new_query_sql_parameters}
    {:ok, query}
  end

  defp get_query_param_from_overrides(overrides, query_mapping_id) do
    Enum.find(overrides, fn map ->
      map["dashboard_query_mapping_id"] == query_mapping_id
    end)
  end

  # Private functions

  defp store_execution_data_async(result, user_id) do
    # When a Clickhouse query is executed, the query details are buffered in
    # memory for up to 7500ms before they flush to the database table.
    # Because of this, storing the execution data is done in a separate process
    # to avoid blocking the main process and to return the result to the user
    # faster.
    Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
      QueryExecution.store_execution(result, user_id)
    end)
  end

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
