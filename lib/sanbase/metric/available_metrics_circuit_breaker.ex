defmodule Sanbase.Metric.AvailableMetricsCircuitBreaker do
  @moduledoc """
  Per-module circuit breaker for the
  `Sanbase.Metric.available_metrics_for_selector/2` fan-out.

  The main entry point is `call/2`: it runs one module's available-metrics
  probe guarded by the breaker - skipping it while the breaker is open, timing
  it, logging slow probes, normalizing malformed returns and scoring the
  outcome. `Sanbase.Metric` only supplies the probe function and stays free of
  the mechanics.

  A breaker instance is identified by an
  `{module, selector, access_level, lookback_days}` tuple and its state lives in
  `Sanbase.Cache`, so it is effectively a distributed breaker with implicit,
  TTL-driven half-open transitions rather than an in-process state machine.

  States (closed = healthy/probing, open = tripped/skipping):

    * **Closed** - normal. Every probe is attempted; failures accumulate a
      weighted score. In practice modules fail far more often because they are
      slow and time out than because of a real error, so the two are weighted
      differently: a timeout-flavored failure costs `@timeout_weight` and a hard
      error costs `@error_weight`. The breaker does not trip until the score
      reaches `@trip_threshold` - e.g. 6 consecutive timeouts or 3 consecutive
      hard errors (or any mix in between).
    * **Open** - once tripped, the module is skipped (fail fast with
      `{:error, {:circuit_open, reason}}`) for `@open_ttl` seconds. The window
      is deliberately short - roughly one RehydratingCache refresh cycle - so a
      module that was merely slow is retried quickly; the fan-out result stays
      `:nocache`, so retries keep coming on every tick.
    * **Half-open** - once the open window expires the next probe is a trial
      (the `Sanbase.Cache` lock serializes it to one). Success closes the
      breaker and resets the score; a failure pushes the score further past the
      threshold and re-opens immediately.

  Alongside the breaker it keeps a **last-known-good** list per module: every
  successful probe caches the module's list far longer than the working cache, so
  while the breaker is open (or a module is simply failing) the fan-out can serve
  that slightly stale list instead of dropping the module's metrics - available
  metrics are stable reference data, so stale beats absent.

  Accounting is deliberately approximate: concurrent same-selector callers may
  occasionally record the same slow window twice (both their tasks get killed),
  and racing increments can lose an update. Both are tolerable because a
  premature trip only costs one short open window during which the stale list is
  still served.

  The whole mechanism can be disabled with the
  `AVAILABLE_METRICS_CIRCUIT_BREAKER_ENABLED` env var (see `enabled?/0`). When
  disabled the breaker never opens, nothing is scored, and no stale list is
  served - every probe runs unguarded. Probe timing/slow-probe logging and
  result normalization still apply: they are probe-execution concerns that
  predate the breaker (normalization keeps a malformed module return from being
  cached as a success), not breaker state.
  """

  require Logger

  alias Sanbase.Utils.Config

  @typedoc """
  Identifies one breaker instance: the metric-adapter module plus the selector
  and options that shape its available-metrics probe.
  """
  @type id ::
          {module(), selector :: any(), access_level :: String.t(),
           lookback_days :: non_neg_integer() | nil}

  @type probe_result :: {:ok, list(String.t())} | {:error, any()}

  # Failure weights and trip threshold - rationale in the moduledoc.
  @timeout_weight 1
  @error_weight 2
  @trip_threshold 6

  # Open window (seconds). 15s skips roughly one ~20s RehydratingCache refresh
  # cycle, so a module that was merely slow is retried within ~40s.
  @open_ttl 15

  # Sliding window (seconds) the score survives between failures: every recorded
  # failure refreshes the TTL; a longer quiet gap starts the count fresh.
  @failure_window 180

  # Last-known-good list lifetime. Bounded by Sanbase.Cache's 24h max TTL.
  @last_good_ttl 86_400

  # Log a probe that exceeds this, so the "slow upstream" hint in the resolver
  # timeout maps to a concrete culprit.
  @slow_probe_log_threshold_ms 5_000

  @doc """
  Run one module's probe guarded by the breaker and return its
  `{:ok, _} | {:error, _}` result.

  While the breaker is open the probe is skipped and `{:error, {:circuit_open,
  reason}}` is returned - a shape distinct from a fresh failure, so it is never
  scored and the open window expires on its own. Otherwise the probe runs and
  is timed (slow probes are logged), its return is normalized (a malformed
  non-ok/non-error value becomes `{:error, {:invalid_result, _}}` so it is
  never cached as a success) and the outcome is scored: success stores the
  last-known-good list and closes the breaker, failure counts toward tripping
  it.

  Meant to be called inside the working-cache's `get_or_store` compute function
  so the lock serializes the open-check against the failure write: a cached
  value bypasses both, so cached results always win.

  When the breaker is disabled the probe always runs and nothing is scored;
  timing, slow-probe logging and normalization apply regardless (see the
  moduledoc).
  """
  @spec call(id, (-> any())) :: probe_result
  def call({_module, _selector, _access_level, _lookback_days} = id, fun)
      when is_function(fun, 0) do
    case check(id) do
      {:open, reason} ->
        {:error, {:circuit_open, reason}}

      :closed ->
        {elapsed_us, result} = :timer.tc(fun)
        maybe_log_slow_probe(id, elapsed_us)

        result = normalize_result(result)
        record_probe_result(result, id)
        result
    end
  end

  @doc """
  Whether the circuit breaker is active. Controlled by the
  `AVAILABLE_METRICS_CIRCUIT_BREAKER_ENABLED` env var (default enabled); when
  false, `call/2` always runs the probe unguarded and `last_good/1` returns `[]`.
  """
  @spec enabled?() :: boolean()
  def enabled?() do
    value =
      :sanbase
      |> Application.get_env(__MODULE__, [])
      |> Keyword.get(:enabled, {:system, "AVAILABLE_METRICS_CIRCUIT_BREAKER_ENABLED", "true"})
      |> Config.parse_config_value()
      |> to_string()
      |> String.downcase()

    value in ["true", "1"]
  end

  @doc """
  Current breaker state for `id`: `{:open, reason}` while tripped, `:closed`
  otherwise (always `:closed` when disabled).
  """
  @spec check(id) :: :closed | {:open, any()}
  def check(id) do
    if enabled?() do
      case Sanbase.Cache.get(open_key(id)) do
        {:open, reason} -> {:open, reason}
        nil -> :closed
      end
    else
      :closed
    end
  end

  @doc """
  Score failures that could not report themselves through `call/2` - in practice
  a task killed on the fan-out timeout, which surfaces as `{:exit, :timeout}` in
  the results. `{:ok, _}` and `{:error, _}` results are skipped: they already
  self-reported inside `call/2`, and open short-circuits arrive as
  `{:error, {:circuit_open, _}}` so they cannot inflate the score while the
  breaker is already open.
  """
  @spec record_uncaught_failures([{module(), any()}], any(), String.t(), any()) :: :ok
  def record_uncaught_failures(tagged_results, selector, access_level, lookback_days) do
    if enabled?() do
      Enum.each(tagged_results, fn
        {_module, {:ok, _}} ->
          :ok

        {_module, {:error, _}} ->
          :ok

        {module, failure} ->
          record_failure(failure, {module, selector, access_level, lookback_days})
      end)
    end

    :ok
  end

  @doc """
  The last-known-good metrics list for `id`, or `[]` if none is cached (or the
  breaker is disabled). Lets the fan-out keep a failing module's metrics in the
  combined result.
  """
  @spec last_good(id) :: list(String.t())
  def last_good(id) do
    if enabled?() do
      case Sanbase.Cache.get(last_good_key(id)) do
        nil -> []
        metrics -> metrics
      end
    else
      []
    end
  end

  @doc """
  Current accumulated failure score for `id` (0 if none). Diagnostics/tests.
  """
  @spec failure_score(id) :: non_neg_integer()
  def failure_score(id) do
    Sanbase.Cache.get(score_key(id)) || 0
  end

  @doc """
  Force the breaker closed for `id` by clearing its open marker, so the next
  probe runs immediately. Used by tests to simulate the open window expiring
  without waiting out the TTL.
  """
  @spec close(id) :: :ok
  def close(id) do
    Sanbase.Cache.clear(open_key(id))
  end

  # A probe must return `{:ok, _}` or `{:error, _}`. Any other shape would be
  # written to the per-module cache as a success (errors are the only shape
  # `Sanbase.Cache.store` refuses) and then replayed from the cache on every
  # call, confusing both the fan-out and the failure scoring. Normalize it to
  # an error so it stays uncached and is scored like any other failure.
  defp normalize_result({:ok, _} = ok), do: ok
  defp normalize_result({:error, _} = error), do: error
  defp normalize_result(other), do: {:error, {:invalid_result, other}}

  defp record_probe_result(result, id) do
    if enabled?() do
      case result do
        {:ok, metrics} ->
          store_last_good(metrics, id)
          reset(id)

        {:error, reason} ->
          record_failure(reason, id)
      end
    end

    :ok
  end

  # Add the failure's weight to the sliding-window score and trip the breaker
  # once the threshold is reached. The score is not reset on trip (only on
  # success), so a half-open failure - which pushes the score further past the
  # threshold - re-opens immediately.
  defp record_failure(reason, id) do
    score_key = score_key(id)
    score = (Sanbase.Cache.get(score_key) || 0) + failure_weight(reason)
    Sanbase.Cache.store({score_key, @failure_window}, score)

    if score >= @trip_threshold do
      Sanbase.Cache.store({open_key(id), @open_ttl}, {:open, reason})
    end
  end

  # Timeout-flavored failures weigh less than hard errors. The inspect-based
  # sniff uniformly catches the fan-out kill (`{:exit, :timeout}`), ClickHouse
  # "Timeout exceeded" error strings and DBConnection timeout exceptions; a
  # false positive only makes the breaker more tolerant, which is safe.
  defp failure_weight(failure) do
    timeout? =
      failure
      |> inspect()
      |> String.downcase()
      |> String.contains?("timeout")

    if timeout?, do: @timeout_weight, else: @error_weight
  end

  defp reset(id) do
    Sanbase.Cache.clear(score_key(id))
    Sanbase.Cache.clear(open_key(id))
  end

  defp store_last_good(metrics, id) do
    Sanbase.Cache.store({last_good_key(id), @last_good_ttl}, metrics)
  end

  defp maybe_log_slow_probe({module, selector, _access_level, _lookback_days}, elapsed_us) do
    elapsed_ms = div(elapsed_us, 1000)

    if elapsed_ms >= @slow_probe_log_threshold_ms do
      Logger.warning(
        "slow available_metrics module: #{inspect(module)} took #{elapsed_ms}ms " <>
          "for selector=#{inspect(selector)}"
      )
    end

    :ok
  end

  defp open_key(id), do: key(:available_metrics_circuit_open, id)
  defp score_key(id), do: key(:available_metrics_circuit_score, id)
  defp last_good_key(id), do: key(:available_metrics_circuit_last_good, id)

  defp key(tag, {module, selector, access_level, lookback_days}) do
    {__MODULE__, tag, module, selector, access_level, lookback_days}
    |> Sanbase.Cache.hash()
  end
end
