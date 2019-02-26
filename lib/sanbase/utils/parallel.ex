defmodule Sanbase.Parallel do
  @doc ~s"""
  Module implementing parallel and concurrent versions of enumerable map and filter functions.
  """

  @default_timeout 15_000

  def preject(collection, func, opts) when is_function(func, 1) do
    timeout = Keyword.get(opts, :timeout) || @default_timeout

    collection
    |> Enum.map(&Task.async(fn -> func.(&1) end))
    |> Enum.map(&Task.await(&1, timeout))

    collection
    |> Stream.map(&Task.async(fn -> {func.(&1), &1} end))
    |> Stream.map(&Task.await(&1, timeout))
    |> Stream.reject(fn {bool, _item} -> bool === true end)
    |> Enum.map(fn {_bool, item} -> item end)
  end

  def pfilter(collection, func, opts) when is_function(func, 1) do
    preject(collection, &(not func.(&1)), opts)
  end

  def pmap(collection, func, opts \\ []) when is_function(func, 1) do
    timeout = Keyword.get(opts, :timeout) || @default_timeout

    collection
    |> Enum.map(&Task.async(fn -> func.(&1) end))
    |> Enum.map(&Task.await(&1, timeout))
  end

  def flat_pmap(collection, func, opts \\ []) when is_function(func, 1) do
    timeout = Keyword.get(opts, :timeout) || @default_timeout

    collection
    |> Enum.map(&Task.async(fn -> func.(&1) end))
    |> Enum.flat_map(&Task.await(&1, timeout))
  end

  def pmap_concurrent(collection, func, opts \\ []) when is_function(func, 1) do
    max_concurrency = Keyword.get(opts, :max_concurrency) || System.schedulers_online()
    ordered = Keyword.get(opts, :ordered) || true
    timeout = Keyword.get(opts, :timeout) || @default_timeout
    on_timeout = Keyword.get(opts, :on_timeout) || :exit
    map_type = Keyword.get(opts, :map_type) || :map

    stream =
      Task.Supervisor.async_stream_nolink(
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
          {:ok, elem} ->
            elem

          data ->
            data
        end)

      :flat_map ->
        stream
        |> Enum.flat_map(fn
          {:ok, elem} ->
            elem

          data ->
            data
        end)
    end
  end

  def pfilter_concurrent(collection, func, opts \\ []) when is_function(func, 1) do
    filter_func = fn x -> {func.(x), x} end

    pmap_concurrent(collection, filter_func, opts)
    |> Enum.filter(fn {bool, _item} -> bool === true end)
    |> Enum.map(fn {_bool, item} -> item end)
  end

  def preject_concurrent(collection, func, opts \\ []) when is_function(func, 1) do
    reject_func = fn x -> not func.(x) end
    pfilter_concurrent(collection, reject_func, opts)
  end
end
