defmodule Sanbase.TestHelpers do
  @moduledoc false
  def wait_event_bus_subscriber(topic) do
    if Sanbase.EventBusTest.EventBusTestSubscriber in EventBus.subscribers(topic) do
      :ok
    else
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
        Sanbase.TaskSupervisor
        |> Task.Supervisor.children()
        |> Enum.map(fn child ->
          Task.Supervisor.terminate_child(Sanbase.TaskSupervisor, child)
        end)
      end)
    end
  end

  def generate_datetimes(from, interval, count) when count >= 1 do
    interval_sec = Sanbase.DateTimeUtils.str_to_sec(interval)

    Enum.map(0..(count - 1), fn offset -> Timex.shift(from, seconds: interval_sec * offset) end)
  end
end
