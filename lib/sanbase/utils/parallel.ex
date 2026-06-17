defmodule Sanbase.Parallel do
  @doc ~s"""
  Module implementing concurrent map and filter functions on enumerable under Sanbase.TaskSupervisor
  """

  @default_timeout 25_000

  def flat_map(collection, func, opts \\ [])

  def flat_map(collection, func, opts) do
    map(collection, func, Keyword.put(opts, :map_type, :flat_map))
  end

  def map(collection, func, opts \\ []) when is_function(func, 1) do
    max_concurrency = Keyword.get(opts, :max_concurrency) || 2 * System.schedulers_online()
    # Default arg, not `|| true`: `false || true` would coerce an explicit
    # `ordered: false` back to `true`, silently forcing ordering. All
    # existing `ordered: false` callers collect into maps / sums (order
    # independent), so honoring the flag changes throughput, not results.
    ordered = Keyword.get(opts, :ordered, true)
    timeout = Keyword.get(opts, :timeout) || @default_timeout
    on_timeout = Keyword.get(opts, :on_timeout) || :exit
    map_type = Keyword.get(opts, :map_type) || :map

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
        on_timeout: on_timeout
      )

    case map_type do
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

  defp wrap_with_request_context(func, nil), do: func

  defp wrap_with_request_context(func, %Sanbase.RequestContext{} = ctx) do
    fn x ->
      Sanbase.RequestContext.put_logger_metadata(ctx)
      func.(x)
    end
  end
end
