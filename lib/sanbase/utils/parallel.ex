defmodule Sanbase.Parallel do
  @doc ~s"""

  """
  def pmap(collection, func, opts \\ []) when is_function(func, 1) do
    timeout = Keyword.get(opts, :timeout) || 5_000

    collection
    |> Enum.map(&Task.async(fn -> func.(&1) end))
    |> Enum.map(&Task.await(&1, timeout))
  end

  def pmap_concurrent(collection, func, opts \\ []) when is_function(func, 1) do
    max_concurrency = Keyword.get(opts, :max_concurrency) || System.schedulers_online()
    ordered = Keyword.get(opts, :ordered) || true
    timeout = Keyword.get(opts, :timeout) || 5_000
    on_timeout = Keyword.get(opts, :on_timeout) || :exit

    Task.Supervisor.async_stream_nolink(
      Sanbase.TaskSupervisor,
      collection,
      func,
      ordered: ordered,
      max_concurrency: max_concurrency,
      timeout: timeout,
      on_timeout: on_timeout
    )
    |> Enum.map(fn {:ok, elem} -> elem end)
  end
end
