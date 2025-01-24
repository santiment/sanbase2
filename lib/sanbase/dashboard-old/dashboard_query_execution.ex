defmodule Sanbase.Dashboard.QueryExecution do
  @moduledoc ~s"""
  TODO
  """
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Dashboard
  alias Sanbase.Accounts.User

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

  schema "clickhouse_query_executions" do
    belongs_to(:user, User)

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
    credits_cost =
      from(c in __MODULE__,
        where:
          c.user_id == ^user_id and c.inserted_at >= ^from and
            c.inserted_at <= ^to,
        select: sum(c.credits_cost)
      )
      |> Sanbase.Repo.one()

    {:ok, credits_cost || 0}
  end

  @fields [
    :user_id,
    :clickhouse_query_id,
    :execution_details,
    :credits_cost,
    :query_start_time,
    :query_end_time
  ]

  @doc ~s"""
  Store a query execution run by a user. It computes the credits cost
  of the computation and stores it alongside some metadata.

  The data is stored in the system.query_log table
  """
  @spec store_execution(user_id, Dashboard.Query.Result.t()) ::
          {:ok, t()} | {:error, Ecto.Changeset.t()}
  def store_execution(user_id, query_result, attempts_left \\ 3) do
    # The query_log needs 7.5 seconds to be flushed to disk. Trying to
    # read the data before that can result in an empty result
    Process.sleep(8000)

    %{credits_cost: credits_cost, execution_details: execution_details} =
      compute_credits_cost(query_result)

    credits_cost = [credits_cost, 1] |> Enum.max() |> trunc()

    # credits_cost is stored outside the execution_details as it's not
    # really an execution detail, but a business logic detail. Also having
    # it in a separate field makes it easier to compute the total credits spent

    args =
      query_result
      |> Map.take([
        :clickhouse_query_id,
        :query_start_time,
        :query_end_time
      ])
      |> Map.merge(%{
        credits_cost: credits_cost,
        user_id: user_id,
        execution_details: execution_details
      })

    %__MODULE__{}
    |> cast(args, @fields)
    |> validate_required(@fields)
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
  @spec get_execution_stats(String.t(), non_neg_integer()) ::
          {:ok, t()} | {:error, String.t()}
  def get_execution_stats(clickhouse_query_id, attempts_left \\ 2) do
    query =
      from(
        qe in __MODULE__,
        where: qe.clickhouse_query_id == ^clickhouse_query_id
      )

    case Sanbase.Repo.one(query) do
      %__MODULE__{} = query_execution ->
        {:ok, query_execution}

      nil ->
        case attempts_left do
          0 ->
            {:error, "Query execution not found"}

          _ ->
            get_execution_stats(clickhouse_query_id, attempts_left - 1)
        end
    end
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

    # The credits cost is computed as the dot product of the vectors
    # representing the stats' values and the weights, i.e
    # value(read_gb)*weight(read_gb) + value(result_gb)*weight(result_gb) + ...
    # The values for the weights are manually picked. They are going to be tuned
    # as times go by.
    weights = %{
      read_compressed_gb: 0.2,
      cpu_time_microseconds: 0.0000007,
      query_duration_ms: 0.005,
      memory_usage_gb: 20,
      read_rows: 0.00000001,
      read_gb: 0.05,
      result_rows: 0.001,
      result_gb: 2000
    }

    credits_cost =
      Map.merge(execution_details, weights, fn _k, value, weight ->
        value * weight
      end)
      |> Map.values()
      |> Enum.sum()
      |> trunc()

    %{execution_details: execution_details, credits_cost: credits_cost}
  end

  defp get_execution_details(query_id, event_time_start) do
    query_struct = get_execution_details_query(query_id, event_time_start)

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

  defp get_execution_details_query(query_id, event_time_start) do
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
      query_id = {{query_id}} AND
      type = 'QueryFinish' AND
      event_time >= toDateTime({{datetime}}) - INTERVAL 1 MINUTE AND
      event_time <= toDateTime({{datetime}}) + INTERVAL 1 MINUTE
    """

    params = %{
      query_id: query_id,
      datetime: DateTime.to_unix(event_time_start)
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end
end
