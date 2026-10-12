defmodule Sanbase.Parallel do
  @doc ~s"""
  Module implementing concurrent map and filter functions on enumerable under Sanbase.TaskSupervisor
  """

  require Logger

  @default_timeout 25_000

  def flat_map(collection, func, opts \\ [])

  def flat_map(collection, func, opts) do
    map(collection, func, Keyword.put(opts, :map_type, :flat_map))
  end

  # Fan-out budget inside Dataloader.KV batches: above CH 85s, below KV 105s. See docs/timeouts.md.
  def dataloader_timeout(), do: 95_000

  @doc ~s"""
  `on_timeout:` also accepts `:drop`, which kills a timed out task, logs a warning
  (prefixed with `:label`) and leaves its input out of the result.
  """
  def map(collection, func, opts \\ []) when is_function(func, 1) do
    stream = stream(collection, func, opts)

    case Keyword.get(opts, :map_type) || :map do
      :map ->
        stream
        |> Enum.map(fn
          {:ok, elem} -> elem
          data -> data
        end)

      :flat_map ->
        stream
        |> Enum.flat_map(fn
          {:ok, elem} -> elem
          data -> data
        end)
    end
  end

  @doc ~s"""
  Like `map/3` for a `func` returning `{:ok, result}` or `{:error, reason}`.
  Returns `{:ok, results}` only if every task succeeds in time, otherwise the first
  `{:error, reason}`. A timed out task is killed and becomes `{:error, {:exit, reason}}`.
  """
  def map_or_error(collection, func, opts \\ []) when is_function(func, 1) do
    # Reducing the stream itself, halting it shuts down the tasks still running
    collection
    |> stream(func, Keyword.put(opts, :on_timeout, :kill_task))
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, {:ok, result}}, {:ok, acc} -> {:cont, {:ok, [result | acc]}}
      {:ok, {:error, _} = error}, _acc -> {:halt, error}
      {:exit, reason}, _acc -> {:halt, {:error, {:exit, reason}}}
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      error -> error
    end
  end

  def filter(collection, func, opts \\ []) when is_function(func, 1) do
    filter_func = fn x -> {func.(x), x} end

    map(collection, filter_func, opts)
    |> Enum.filter(fn {bool, _item} -> bool === true end)
    |> Enum.map(fn {_bool, item} -> item end)
  end

  def reject(collection, func, opts \\ []) when is_function(func, 1) do
    reject_func = fn x -> not func.(x) end
    filter(collection, reject_func, opts)
  end

  defp stream(collection, func, opts) do
    max_concurrency = Keyword.get(opts, :max_concurrency) || 2 * System.schedulers_online()
    # Default arg, not `|| true`: `false || true` would coerce an explicit
    # `ordered: false` back to `true`, silently forcing ordering. All
    # existing `ordered: false` callers collect into maps / sums (order
    # independent), so honoring the flag changes throughput, not results.
    ordered = Keyword.get(opts, :ordered, true)
    timeout = Keyword.get(opts, :timeout) || @default_timeout
    on_timeout = Keyword.get(opts, :on_timeout) || :exit
    drop? = on_timeout == :drop

    # `Task.Supervisor` workers do NOT inherit `Logger.metadata`. Callers
    # that need the per-request `Sanbase.RequestContext` (for ClickHouse
    # masking SETTINGS, the OTP logger filter, etc.) must pass it
    # explicitly via the `:request_context` option — we do the
    # cross-process re-seed inside each worker. No `:request_context`
    # means no propagation; the workers run with empty metadata.
    func = wrap_with_request_context(func, Keyword.get(opts, :request_context))

    stream =
      Task.Supervisor.async_stream(
        Sanbase.TaskSupervisor,
        collection,
        func,
        ordered: ordered,
        max_concurrency: max_concurrency,
        timeout: timeout,
        on_timeout: if(drop?, do: :kill_task, else: on_timeout),
        zip_input_on_exit: drop? or Keyword.get(opts, :zip_input_on_exit, false)
      )

    if drop?, do: drop_timed_out(stream, Keyword.get(opts, :label)), else: stream
  end

  # Other exits are kept in the result, so the caller sees them
  defp drop_timed_out(stream, label) do
    Stream.reject(stream, fn
      {:exit, {input, :timeout}} ->
        Logger.warning(
          "#{label || "Sanbase.Parallel"} dropped a timed out task for #{inspect(input, limit: 5)}"
        )

        true

      _ ->
        false
    end)
  end

  defp wrap_with_request_context(func, nil), do: func

  defp wrap_with_request_context(func, %Sanbase.RequestContext{} = ctx) do
    fn x ->
      Sanbase.RequestContext.put_logger_metadata(ctx)
      func.(x)
    end
  end
end
