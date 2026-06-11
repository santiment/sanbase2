defmodule Sanbase.Queries.QueryExecution do
  @moduledoc ~s"""
  Store and retrieve the details of the query executions.

  The details of the query execution are obtained from Clickhouse based on
  the given clickhouse query_id. Clickhouse holds the executed queries stats
  in memory and dumps them to the disk only once every 7500ms. This module
  needs to account for this behavior.

  The details with the addition of the credits spent comptued are then stored in Postgres,
  from where user summaries are computed.
  """
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Queries.Executor.Result
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

  # Users with `activity_traces_hidden` set log_queries=0 in their
  # ClickHouse SETTINGS, so `system.query_log` has no row for them and
  # the full per-execution stats are unavailable. We fall back to the
  # subset of metrics in the driver's HTTP summary (read_rows /
  # read_bytes / result_rows / result_bytes / elapsed_ns) and multiply
  # by this factor to cover the missing memory_usage_gb +
  # cpu_time_microseconds + read_compressed_gb terms AND act as a
  # privacy premium baked into their enterprise contract.
  @activity_traces_hidden_multiplier 2
  @bytes_per_gb 1_073_741_824

  # Flat credits charge for an `activity_traces_hidden` execution whose
  # HTTP summary is entirely missing (driver failure/timeout). We can't
  # measure the real cost and won't drop the billing row, so charge a
  # modest non-trivial default — deliberately above the module minimum
  # of 1 so an unmeasured query can't be effectively free. Summary
  # gaps are rare; when present the real per-query formula is used.
  @summary_missing_credits_cost 10

  @timestamps_opts [type: :utc_datetime]
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
          {:ok, non_neg_integer}
  def credits_spent(user_id, from, to) do
    query =
      from(
        c in __MODULE__,
        where:
          c.user_id == ^user_id and c.inserted_at >= ^from and
            c.inserted_at <= ^to,
        select: sum(c.credits_cost)
      )

    {:ok, Sanbase.Repo.one(query) || 0}
  end

  @doc ~s"""
  Return a query that computes the summary of the user's executions.

  The summary includes the total credits spent in the current month and amount of
  queries executed in the current minute, hour and day.
  Only the queries that have non-zero credits cost are counted. The only way a query
  can have a zero cost is if it has been set to zero by a moderator/admin. This happens
  when a moderator/admin clears the user's queries to reset their limits via the admin
  panel.
  """
  @spec executions_summary(user_id) :: Ecto.Query.t()
  def executions_summary(user_id) do
    now = DateTime.utc_now()
    beginning_of_minute = %{now | :second => 0, :microsecond => {0, 0}}
    beginning_of_hour = %{now | :minute => 0, :second => 0, :microsecond => {0, 0}}
    beginning_of_day = Timex.beginning_of_day(now)
    beginning_of_month = Timex.beginning_of_month(now)

    from(c in __MODULE__,
      # The c.credits_cost > 0 is added to avoid counting the queries that have been "cleared"
      # when a moderator/admin has cleared the user's queries to reset their limits. If they
      # are counted, the user might still be restricted after cleaning their limits.
      where:
        c.user_id == ^user_id and c.inserted_at >= ^beginning_of_month and c.credits_cost > 0,
      select: %{
        monthly_credits_spent: coalesce(sum(c.credits_cost), 0),
        queries_executed_minute:
          fragment("COUNT(CASE WHEN inserted_at >= ? THEN 1 ELSE NULL END)", ^beginning_of_minute),
        queries_executed_hour:
          fragment("COUNT(CASE WHEN inserted_at >= ? THEN 1 ELSE NULL END)", ^beginning_of_hour),
        queries_executed_day:
          fragment("COUNT(CASE WHEN inserted_at >= ? THEN 1 ELSE NULL END)", ^beginning_of_day),
        queries_executed_month:
          fragment("COUNT(CASE WHEN inserted_at >= ? THEN 1 ELSE NULL END)", ^beginning_of_month)
      }
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
  @spec store_execution(Result.t(), user_id, non_neg_integer()) ::
          {:ok, t()} | {:error, Ecto.Changeset.t()}
  def store_execution(query_result, user_id, wait_fetching_details_ms, attempts_left \\ 3) do
    %{credits_cost: credits_cost, execution_details: execution_details} =
      if Sanbase.Accounts.activity_traces_hidden?(user_id) do
        # `system.query_log` has no row for this user (log_queries=0),
        # so skip the flush wait + lookup entirely and compute from the
        # driver's HTTP summary instead.
        compute_credits_cost_from_summary(query_result)
      else
        # The query_log needs 7.5 seconds to be flushed to disk. Trying to
        # read the data before that can result in an empty result. The wait_fetching_details_ms
        # can be changed in tests to speed up the tests
        Process.sleep(wait_fetching_details_ms)
        compute_credits_cost(query_result)
      end

    credits_cost = [credits_cost, 1] |> Enum.max() |> Kernel.trunc()

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
    _e ->
      # This can happen if the query details are not flushed to the system.query_log
      # table or some other clickouse error occurs. Allow for 3 attempts in total before
      # reraising the exception.

      case attempts_left <= 0 do
        true ->
          {:error, "Cannot store execution"}

        false ->
          store_execution(query_result, user_id, wait_fetching_details_ms, attempts_left - 1)
      end
  end

  @doc ~s"""
  Get the execution stats for a query owned by `user_id`.

  Constrained by `user_id` so a holder of someone else's
  `clickhouse_query_id` (a UUID, but still a small enumerable secret)
  cannot read foreign execution stats.

  The stats include information about how many rows and bytes have been
  read from the disk, how much CPU time was used, how big is the result, etc.
  """
  @spec get_execution_stats(String.t(), user_id, non_neg_integer()) ::
          {:ok, t()} | {:error, String.t()}
  def get_execution_stats(clickhouse_query_id, user_id, attempts_left \\ 2) do
    query =
      from(
        qe in __MODULE__,
        where: qe.clickhouse_query_id == ^clickhouse_query_id and qe.user_id == ^user_id
      )

    case Sanbase.Repo.one(query) do
      %__MODULE__{} = query_execution ->
        {:ok, %{execution_details: d} = query_execution}
        atomized = Map.new(d, fn {k, v} -> {String.to_existing_atom(k), v} end)

        {:ok, Map.put(query_execution, :execution_details, atomized)}

      nil ->
        case attempts_left do
          0 ->
            {:error, "Query execution for clickhouse query id #{clickhouse_query_id} not found"}

          _ ->
            Process.sleep(5000)
            get_execution_stats(clickhouse_query_id, user_id, attempts_left - 1)
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

  @spec get_user_monthly_executions(user_id, Keyword.t()) :: Ecto.Query.t()
  def get_user_monthly_executions(user_id, opts) do
    beginning_of_month = Timex.beginning_of_month(DateTime.utc_now())

    from(
      qe in __MODULE__,
      where: qe.user_id == ^user_id and qe.inserted_at >= ^beginning_of_month,
      order_by: [desc: qe.id]
    )
    |> maybe_preload(opts)
  end

  # Private functions

  # Credits cost for an `activity_traces_hidden` user. The driver's HTTP
  # `summary` map gives us 5 of the 8 fields the regular formula uses;
  # the remaining 3 (memory_usage_gb, cpu_time_microseconds,
  # read_compressed_gb) are covered by `@activity_traces_hidden_multiplier`.
  defp compute_credits_cost_from_summary(%Result{summary: %{} = summary}) do
    read_rows = summary_int(summary, "read_rows")
    read_bytes = summary_int(summary, "read_bytes")
    result_rows = summary_int(summary, "result_rows")
    result_bytes = summary_int(summary, "result_bytes")
    elapsed_ns = summary_int(summary, "elapsed_ns")

    read_gb = read_bytes / @bytes_per_gb
    result_gb = result_bytes / @bytes_per_gb
    query_duration_ms = elapsed_ns / 1_000_000

    partial_cost =
      read_rows * @credit_cost_weights.read_rows +
        read_gb * @credit_cost_weights.read_gb +
        result_rows * @credit_cost_weights.result_rows +
        result_gb * @credit_cost_weights.result_gb +
        query_duration_ms * @credit_cost_weights.query_duration_ms

    credits_cost =
      (partial_cost * @activity_traces_hidden_multiplier)
      |> Float.round()
      |> trunc()
      |> max(1)

    execution_details = %{
      read_rows: read_rows,
      read_gb: Float.round(read_gb, 6),
      result_rows: result_rows,
      result_gb: Float.round(result_gb, 6),
      query_duration_ms: Float.round(query_duration_ms, 3),
      # Unavailable without `system.query_log`; zeroed so the
      # `non_null(:float)` fields on `:sql_query_execution_stats` still
      # resolve for protected users.
      read_compressed_gb: 0.0,
      cpu_time_microseconds: 0.0,
      memory_usage_gb: 0.0,
      source: "summary_only",
      multiplier: @activity_traces_hidden_multiplier
    }

    %{credits_cost: credits_cost, execution_details: execution_details}
  end

  # Driver timeout / failure can leave summary as nil. Fall back to a
  # flat safe minimum so the billing row is still written and the user
  # is still accounted for, instead of crashing through the rescue and
  # dropping the execution entirely. All stat fields are zeroed so the
  # `non_null(:float)` fields on `:sql_query_execution_stats` resolve.
  defp compute_credits_cost_from_summary(_) do
    %{
      credits_cost: @summary_missing_credits_cost,
      execution_details: %{
        read_rows: 0.0,
        read_gb: 0.0,
        result_rows: 0.0,
        result_gb: 0.0,
        query_duration_ms: 0.0,
        read_compressed_gb: 0.0,
        cpu_time_microseconds: 0.0,
        memory_usage_gb: 0.0,
        source: "summary_missing",
        multiplier: @activity_traces_hidden_multiplier
      }
    }
  end

  defp summary_int(summary, key) do
    case Map.get(summary, key) do
      n when is_integer(n) ->
        n

      n when is_float(n) ->
        trunc(n)

      s when is_binary(s) ->
        case Integer.parse(s) do
          {n, _} -> n
          :error -> 0
        end

      _ ->
        0
    end
  end

  defp compute_credits_cost(args) do
    %{
      clickhouse_query_id: clickhouse_query_id,
      query_start_time: query_start_time
    } = args

    # If there is no result yet this will return {:ok, nil} which will fail and will be retried
    # from inside the rescue block
    {:ok, %{} = execution_details} =
      compute_execution_details(clickhouse_query_id, query_start_time)

    credits_cost =
      execution_details
      |> Enum.reduce(0, fn {key, value}, acc ->
        acc + value * Map.fetch!(@credit_cost_weights, key)
      end)

    # The credits cost cannot be 0. The only way a credits cost can be 0 is if it has been
    # set to 0 by a moderator/admin after it was executed. This happens when a moderator/admin
    # clears the user's executions to reset their limits via the admin panel.
    credits_cost = Enum.max([credits_cost, 1])

    %{execution_details: execution_details, credits_cost: credits_cost}
  end

  defp compute_execution_details(clickhouse_query_id, event_time_start) do
    query_struct = compute_execution_details_query(clickhouse_query_id, event_time_start)

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

  defp compute_execution_details_query(clickhouse_query_id, event_time_start) do
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
    WHERE
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
