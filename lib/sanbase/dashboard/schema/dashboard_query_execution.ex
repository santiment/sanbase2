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

  @type t :: %__MODULE__{
          user_id: user_id(),
          query_id: String.t(),
          execution_details: Map.t(),
          credits_cost: credits_cost(),
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }

  schema "clickhouse_query_executions" do
    belongs_to(:user, User)

    field(:clickhouse_query_id, :string)
    field(:query_id, :string)
    field(:execution_details, :map)
    field(:credits_cost, :integer)

    timestamps()
  end

  @doc ~s"""
  Compute how many credits a user has spent between two datetimes.

  A credit is a unit that measures query's cost. It is computed based on
  the query profiling details - how much RAM memory it used, how much data it
  read from the disk, how big is the result, etc.
  """
  @spec credits_spent(user_id, DateTime.t(), DateTime.t()) :: {:ok, credits_cost()}
  def credits_spent(user_id, from, to) do
    credits_cost =
      from(c in __MODULE__,
        where: c.user_id == ^user_id and c.inserted_at >= ^from and c.inserted_at <= ^to,
        select: sum(c.credits_cost)
      )
      |> Sanbase.Repo.one()

    {:ok, credits_cost || 0}
  end

  @fields [:user_id, :query_id, :clickhouse_query_id, :execution_details, :credits_cost]

  @doc ~s"""
  Store a query execution run by a user. It computes the credits cost
  of the computation and stores it alongside some metadata
  """
  @spec store_execution(user_id, Dashboard.Query.Result.t()) ::
          {:ok, t()} | {:error, Ecto.Changeset.t()}
  def store_execution(user_id, query_result, attempts_left \\ 3) do
    # The query_log needs 7.5 seconds to be flushed to disk. Trying to
    # read the data before that can result in an empty result
    Process.sleep(8000)

    %{credits_cost: credits_cost, execution_details: execution_details} =
      compute_credits_cost(query_result)

    credits_cost =
      Enum.max([Float.round(credits_cost), 1])
      |> Kernel.trunc()

    # credits_cost is stored outside the execution_details as it's not
    # really an execution detail, but a business logic detail. Also having
    # it in a separate field makes it easier to compute the total credits spent
    args =
      query_result
      |> Map.take([:query_id, :clickhouse_query_id])
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
    e ->
      # This can happen if the query details are not flushed to the system.query_log
      # table or some other clickouse error occurs. Allow for 3 attempts in total before
      # reraising the exception.
      case attempts_left do
        0 -> reraise(e, __STACKTRACE__)
        _ -> store_execution(user_id, query_result, attempts_left - 1)
      end
  end

  # Private functions

  defp compute_credits_cost(args) do
    %{clickhouse_query_id: clickhouse_query_id, query_start_time: query_start_time} = args
    {:ok, execution_details} = get_execution_details(clickhouse_query_id, query_start_time)

    # The credits cost is computed as the dot product of the vectors
    # representing the statistics' values and the weights, i.e
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
      Map.merge(execution_details, weights, fn _k, value, weight -> value * weight end)
      |> Map.values()
      |> Enum.sum()

    %{execution_details: execution_details, credits_cost: credits_cost}
  end

  defp get_execution_details(query_id, event_time_start) do
    query = """
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
      query_id = ?1 AND
      type = 'QueryFinish' AND
      event_time >= toDateTime(?2) - INTERVAL 1 MINUTE AND
      event_time <= toDateTime(?2) + INTERVAL 1 MINUTE
    """

    args = [query_id, DateTime.to_unix(event_time_start)]

    Sanbase.ClickhouseRepo.query_transform(
      query,
      args,
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
end
