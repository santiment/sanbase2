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

  # The credits cost is the dot product of the stats' values and these (manually picked)
  # weights: value(read_gb)*weight(read_gb) + value(result_gb)*weight(result_gb) + ...
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

  # `activity_traces_hidden` users set log_queries=0, so `system.query_log` has no row and
  # the full stats are missing. The fallback multiplies the driver's HTTP summary by this
  # factor, covering the absent memory_usage_gb + cpu_time_microseconds +
  # read_compressed_gb terms and acting as the privacy premium in their bespoke contract.
  @activity_traces_hidden_multiplier 2
  @bytes_per_gb 1_073_741_824

  # Flat charge for an `activity_traces_hidden` execution whose HTTP summary is missing
  # (driver failure/timeout): the real cost is unmeasurable but the billing row stays, and
  # this is above the module minimum of 1 so an unmeasured query is not effectively free.
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
      # c.credits_cost > 0 skips queries "cleared" by a moderator resetting the user's
      # limits - counting them would leave the user restricted afterwards.
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
        # No `system.query_log` row for this user (log_queries=0): skip the flush wait and
        # lookup, compute from the driver's HTTP summary.
        compute_credits_cost_from_summary(query_result)
      else
        # The query_log takes 7.5s to flush to disk; reading earlier can come back empty.
        # wait_fetching_details_ms is lowered in tests.
        Process.sleep(wait_fetching_details_ms)
        compute_credits_cost(query_result)
      end

    credits_cost = [credits_cost, 1] |> Enum.max() |> Kernel.trunc()

    # credits_cost is business logic, not an execution detail, and a separate field makes
    # summing the total credits spent easier.

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
      # Happens when the details are not yet flushed to system.query_log, or on another
      # clickhouse error. 3 attempts in total, then reraise.

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
  def get_execution_stats(clickhouse_query_id, querying_user_id, attempts_left \\ 2) do
    query =
      from(
        qe in __MODULE__,
        where: qe.clickhouse_query_id == ^clickhouse_query_id and qe.user_id == ^querying_user_id
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
            get_execution_stats(clickhouse_query_id, querying_user_id, attempts_left - 1)
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

  # Credits for an `activity_traces_hidden` user: the driver's HTTP `summary` gives 5 of
  # the 8 fields the regular formula uses, and `@activity_traces_hidden_multiplier` covers
  # the other 3 (memory_usage_gb, cpu_time_microseconds, read_compressed_gb).
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
      # Unavailable without `system.query_log`; zeroed so the `non_null(:float)` fields on
      # `:sql_query_execution_stats` still resolve for protected users.
      read_compressed_gb: 0.0,
      cpu_time_microseconds: 0.0,
      memory_usage_gb: 0.0,
      source: "summary_only",
      multiplier: @activity_traces_hidden_multiplier
    }

    %{credits_cost: credits_cost, execution_details: execution_details}
  end

  # A driver timeout/failure leaves summary nil. A flat safe minimum still writes the
  # billing row instead of crashing through the rescue and dropping the execution. Stat
  # fields are zeroed so the `non_null(:float)` fields still resolve.
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

    # With no result yet this returns {:ok, nil}, which fails and is retried in the rescue.
    {:ok, %{} = execution_details} =
      compute_execution_details(clickhouse_query_id, query_start_time)

    credits_cost =
      execution_details
      |> Enum.reduce(0, fn {key, value}, acc ->
        acc + value * Map.fetch!(@credit_cost_weights, key)
      end)

    # A credits cost is 0 only if a moderator zeroed it afterwards, clearing the user's
    # executions to reset their limits via the admin panel.
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
