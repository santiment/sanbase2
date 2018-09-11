defmodule Sanbase.ApplicationUtils do
  @doc ~s"""
  Start a worker/supervisor only in particular environment(s).
  Example: Not startuing `MySupervisor` in tests can now be done by replacing
  `{MySupervisor, []}` in the supervisor children by
  `start_in({MySupervisor, []}, [:dev, :prod])`

  INPORTANT NOTE: If you use it, you must use `normalize_children` on the children list.
  """
  def start_in(expr, environments) do
    require Sanbase.Utils.Config, as: Config
    env = Config.module_get(Sanbase, :environment) |> String.to_existing_atom()

    if env in environments do
      expr
    end
  end

  @doc ~s"""
  If `start_in/2` is used it can place `nil` in the place of a worker/supervisor.
  Passing the children through `normalize_children/1` will remove these records.
  """
  def normalize_children(children) do
    children
    |> Enum.reject(&is_nil/1)
  end
end
