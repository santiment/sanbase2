defmodule Sanbase.TestHelpers do
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

  def error_details(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&format_error/1)
  end

  defp format_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(inspect(value)))
    end)
  end
end
