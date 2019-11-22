defmodule Sanbase.TestHelpers do
  defmacro setup_all_with_mocks(mocks, do: setup_block) do
    quote do
      setup_all do
        require Mock
        Mock.mock_modules(unquote(mocks))

        # The mocks are linked to the process that setup all the tests and are
        # automatically unloaded when that process shuts down

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
        |> Enum.map(fn child -> Task.Supervisor.terminate_child(Sanbase.TaskSupervisor, child) end)
      end)
    end
  end

  defmacro clear_kafka_state() do
    quote do
      on_exit(fn ->
        Sanbase.InMemoryKafka.Producer.clear_state()
      end)
    end
  end

  def error_details(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&format_error/1)
  end

  def generate_datetimes(from, interval, count) when count >= 1 do
    interval_sec = Sanbase.DateTimeUtils.str_to_sec(interval)

    0..(count - 1) |> Enum.map(fn offset -> Timex.shift(from, seconds: interval_sec * offset) end)
  end

  defp format_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(inspect(value)))
    end)
  end
end
