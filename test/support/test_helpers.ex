defmodule Sanbase.TestHelpers do
  @moduledoc false

  @doc ~s"""
  `function/0` should return either {:ok, result} or {:error, reason}.

  If the function returns an error, it will be retried `attempts` times, sleeping
  for `sleep` ms in between attempts.
  In case of success, it is immedately returned.
  In case of `attempts` number of errors, the error is returned.
  """
  def try_few_times(function, opts) when is_function(function, 0) do
    attempts = Keyword.fetch!(opts, :attempts)
    sleep = Keyword.fetch!(opts, :sleep)

    case function.() do
      {:ok, result} ->
        {:ok, result}

      {:error, _} = error ->
        if attempts > 1 do
          Process.sleep(sleep)
          try_few_times(function, Keyword.put(opts, :attempts, attempts - 1))
        else
          error
        end
    end
  end

  def wait_event_bus_subscriber(topic) do
    case Sanbase.EventBusTest.EventBusTestSubscriber in EventBus.subscribers(topic) do
      true ->
        :ok

      false ->
        Process.sleep(50)
        wait_event_bus_subscriber(topic)
    end
  end

  defmacro setup_all_with_mocks(mocks, do: setup_block) do
    quote do
      setup_all do
        require Mock
        Mock.mock_modules(unquote(mocks))

        # The mocks are linked to the process that setup all the tests and are
        # automatically unloaded when that process shuts down
        on_exit(fn ->
          :meck.unload()
        end)

        unquote(setup_block)
      end
    end
  end

  defmacro supress_test_console_logging() do
    quote do
      Logger.remove_backend(:console)
      on_exit(fn -> Logger.add_backend(:console) end)
    end
  end

  defmacro clean_task_supervisor_children() do
    quote do
      on_exit(fn ->
        Task.Supervisor.children(Sanbase.TaskSupervisor)
        |> Enum.map(fn child ->
          Task.Supervisor.terminate_child(Sanbase.TaskSupervisor, child)
        end)
      end)
    end
  end

  def generate_datetimes(from, interval, count) when count >= 1 do
    interval_sec = Sanbase.DateTimeUtils.str_to_sec(interval)

    0..(count - 1) |> Enum.map(fn offset -> Timex.shift(from, seconds: interval_sec * offset) end)
  end
end
