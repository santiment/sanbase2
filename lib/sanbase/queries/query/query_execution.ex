defmodule Sanbase.Queries.QueryExecution do
  @moduledoc ~s"""
  TODO
  """
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Dashboard
  alias Sanbase.Accounts.User

  alias Sanbase.Queries.Query

  @type user_id :: non_neg_integer()
  @type credits_cost :: non_neg_integer()

  @type execution_details :: %{
          read_compressed_gb: number(),
          cpu_time_microseconds: number(),
          query_duration_ms: number(),
          memory_usage_gb: number(),
          read_rows: number(),
          read_gb: number(),
          result_rows: number(),
          result_gb: number()
        }

  @type t :: %__MODULE__{
          user_id: user_id(),
          execution_details: execution_details(),
          credits_cost: credits_cost(),
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }

  @preload [:user, :query]

  # The credits cost is computed as the dot product of the vectors
  # representing the stats' values and the weights, i.e
  # value(read_gb)*weight(read_gb) + value(result_gb)*weight(result_gb) + ...
  # The values for the weights are manually picked.
  @credit_cost_weights %{
    read_compressed_gb: 0.2,
    cpu_time_microseconds: 0.0000007,
    query_duration_ms: 0.005,
    memory_usage_gb: 20,
    read_rows: 0.00000001,
    read_gb: 0.05,
    result_rows: 0.001,
    result_gb: 2000
  }
  schema "clickhouse_query_executions" do
    belongs_to(:user, User)
    belongs_to(:query, Query)

    field(:clickhouse_query_id, :string)
    field(:execution_details, :map)
    field(:credits_cost, :integer)

    field(:query_start_time, :naive_datetime)
    field(:query_end_time, :naive_datetime)

    timestamps()
  end

  @doc ~s"""
  Compute how many credits a user has spent between two datetimes.

  A credit is a unit that measures query's cost. It is computed based on
  the query profiling details - how much RAM memory it used, how much data it
  read from the disk, how big is the result, etc.
  """
  @spec credits_spent(user_id, DateTime.t(), DateTime.t()) ::
          {:ok, credits_cost()}
  def credits_spent(user_id, from, to) do
    from(
      c in __MODULE__,
      where:
        c.user_id == ^user_id and c.inserted_at >= ^from and
          c.inserted_at <= ^to,
      select: sum(c.credits_cost)
    )
  end

  @fields [
    :user_id,
    :query_id,
    :clickhouse_query_id,
    :execution_details,
    :credits_cost,
    :query_start_time,
    :query_end_time
  ]

  @required_fields @fields -- [:query_id]

  @doc ~s"""
  Store a query execution run by a user. It computes the credits cost
  of the computation and stores it alongside some metadata.

  The data is stored in the system.query_log table
  """
  @spec store_execution(Dashboard.Query.Result.t(), user_id, non_neg_integer()) ::
          {:ok, t()} | {:error, Ecto.Changeset.t()}
  def store_execution(query_result, user_id, wait_fetching_details_ms, attempts_left \\ 3) do
    # The query_log needs 7.5 seconds to be flushed to disk. Trying to
    # read the data before that can result in an empty result. The wait_fetching_details_ms
    # can be changed in tests to speed up the tests
    Process.sleep(wait_fetching_details_ms)

    %{credits_cost: credits_cost, execution_details: execution_details} =
      compute_credits_cost(query_result)

    credits_cost =
      [Float.round(credits_cost), 1]
      |> Enum.max()
      |> Kernel.trunc()

    # credits_cost is stored outside the execution_details as it's not
    # really an execution detail, but a business logic detail. Also having
    # it in a separate field makes it easier to compute the total credits spent

    args =
      query_result
      |> Map.take([:query_id, :clickhouse_query_id, :query_start_time, :query_end_time])
      |> Map.merge(%{
        credits_cost: credits_cost,
        user_id: user_id,
        execution_details: execution_details
      })

    %__MODULE__{}
    |> cast(args, @fields)
    |> validate_required(@required_fields)
    |> Sanbase.Repo.insert()
  rescue
    _ ->
      # This can happen if the query details are not flushed to the system.query_log
      # table or some other clickouse error occurs. Allow for 3 attempts in total before
      # reraising the exception.
      case attempts_left do
        0 -> {:error, "Cannot store execution"}
        _ -> store_execution(user_id, query_result, attempts_left - 1)
      end
  end

  @doc ~s"""
  Get the execution stats for a query.

  The stats include information about how many rows and bytes have been
  read from the disk, how much CPU time was used, how big is the result, etc.
  """
  @spec get_execution_stats(non_neg_integer(), String.t(), non_neg_integer()) ::
          {:ok, t()} | {:error, String.t()}
  def get_execution_stats(user_id, clickhouse_query_id, attempts_left \\ 2) do
    query =
      from(
        qe in __MODULE__,
        where:
          qe.user_id == ^user_id and
            qe.clickhouse_query_id == ^clickhouse_query_id
      )

    case Sanbase.Repo.one(query) do
      %__MODULE__{} = query_execution ->
        {:ok, query_execution}

      nil ->
        case attempts_left do
          0 ->
            {:error, "Query execution not found"}

          _ ->
            Process.sleep(5000)
            get_execution_stats(user_id, clickhouse_query_id, attempts_left - 1)
        end
    end
  end

  def get_query_execution_by_clickhouse_query_id(clickhouse_query_id, querying_user_id) do
    from(
      qe in __MODULE__,
      where: qe.clickhouse_query_id == ^clickhouse_query_id and qe.user_id == ^querying_user_id
    )
  end

  @doc ~s"""
  Return a list of the executed queries for a user.
  The options' list can contain `:page` and `:page_size` keys
  to control the pagination.
  """
  @spec get_user_query_executions(user_id, Keyword.t()) :: Ecto.Query.t()
  def get_user_query_executions(user_id, opts) do
    from(
      qe in __MODULE__,
      where: qe.user_id == ^user_id,
      order_by: [desc: qe.id]
    )
    |> paginate(opts)
    |> maybe_preload(opts)
  end

  # Private functions

  defp compute_credits_cost(args) do
    %{
      clickhouse_query_id: clickhouse_query_id,
      query_start_time: query_start_time
    } = args

    # If there is no result yet this will return {:ok, nil} which will fail and will be retried
    # from inside the rescue block
    {:ok, %{} = execution_details} = get_execution_details(clickhouse_query_id, query_start_time)

    credits_cost =
      execution_details
      |> Enum.reduce(0, fn {key, value}, acc ->
        acc + value * Map.fetch!(@credit_cost_weights, key)
      end)

    %{execution_details: execution_details, credits_cost: credits_cost}
  end

  defp get_execution_details(clickhouse_query_id, event_time_start) do
    query_struct = get_execution_details_query(clickhouse_query_id, event_time_start)

    Sanbase.ClickhouseRepo.put_dynamic_repo(Sanbase.ClickhouseRepo)

    Sanbase.ClickhouseRepo.query_transform(
      query_struct,
      fn [
           read_compressed_gb,
           cpu_time_microseconds,
           query_duration_ms,
           memory_usage_gb,
           read_rows,
           read_gb,
           result_rows,
           result_gb
         ] ->
        %{
          read_compressed_gb: Float.round(read_compressed_gb, 6),
          cpu_time_microseconds: cpu_time_microseconds,
          query_duration_ms: query_duration_ms,
          memory_usage_gb: Float.round(memory_usage_gb, 6),
          read_rows: read_rows,
          read_gb: Float.round(read_gb, 6),
          result_rows: result_rows,
          result_gb: Float.round(result_gb, 6)
        }
      end
    )
    |> Sanbase.Utils.Transform.maybe_unwrap_ok_value()
  end

  defp get_execution_details_query(clickhouse_query_id, event_time_start) do
    sql = """
    SELECT
      ProfileEvents['ReadCompressedBytes'] / pow(2,30) AS read_compressed_gb,
      ProfileEvents['OSCPUVirtualTimeMicroseconds'] AS cpu_time_microseconds,
      query_duration_ms,
      memory_usage / pow(2, 30) AS memory_usage_gb,
      read_rows,
      read_bytes / pow(2, 30) AS read_gb,
      result_rows,
      result_bytes / pow(2, 30) AS result_gb
    FROM system.query_log_distributed
    PREWHERE
      query_id = {{clickhouse_query_id}} AND
      type = 'QueryFinish' AND
      event_time >= toDateTime({{datetime}}) - INTERVAL 1 MINUTE AND
      event_time <= toDateTime({{datetime}}) + INTERVAL 1 MINUTE
    """

    params = %{
      clickhouse_query_id: clickhouse_query_id,
      datetime: DateTime.to_unix(event_time_start)
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp paginate(query, opts) do
    {limit, offset} = Sanbase.Utils.Transform.opts_to_limit_offset(opts)

    query
    |> limit(^limit)
    |> offset(^offset)
  end

  defp maybe_preload(query, opts) do
    case Keyword.get(opts, :preload?, true) do
      false ->
        query

      true ->
        preload = Keyword.get(opts, :preload, @preload)
        query |> preload(^preload)
    end
  end
end
