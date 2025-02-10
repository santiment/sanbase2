defmodule Sanbase.Parallel do
  @moduledoc false
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
    ordered = Keyword.get(opts, :ordered) || true
    timeout = Keyword.get(opts, :timeout) || @default_timeout
    on_timeout = Keyword.get(opts, :on_timeout) || :exit
    map_type = Keyword.get(opts, :map_type) || :map

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
        Enum.map(stream, fn
          {:ok, elem} -> elem
          data -> data
        end)

      :flat_map ->
        Enum.flat_map(stream, fn
          {:ok, elem} -> elem
          data -> data
        end)
    end
  end

  def filter(collection, func, opts \\ []) when is_function(func, 1) do
    filter_func = fn x -> {func.(x), x} end

    collection
    |> map(filter_func, opts)
    |> Enum.filter(fn {bool, _item} -> bool === true end)
    |> Enum.map(fn {_bool, item} -> item end)
  end

  def reject(collection, func, opts \\ []) when is_function(func, 1) do
    reject_func = fn x -> not func.(x) end
    filter(collection, reject_func, opts)
  end
end
