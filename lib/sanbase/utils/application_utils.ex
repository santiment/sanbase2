defmodule Sanbase.ApplicationUtils do
  require Logger
  alias Sanbase.Utils.Config

  @doc ~s"""
  Get the container type of the currently running pod. It can be one of web,
  signals, scrapers or all. If no container typer is defined, it defaults to all.
  """
  def container_type() do
    System.get_env("CONTAINER_TYPE") || "all"
  end

  @doc ~s"""
  Start a worker/supervisor only in particular environment(s).
  Example: Not startuing `MySupervisor` in tests can now be done by replacing
  `{MySupervisor, []}` in the supervisor children by
  `start_in({MySupervisor, []}, [:dev, :prod])`

  INPORTANT NOTE: If you use it, you must use `normalize_children` on the children list.
  """
  @spec start_in(any(), list[atom()]) :: nil | any
  def start_in(expr, environments) do
    env = Config.module_get(Sanbase, :env)

    if env in environments do
      expr
    end
  end

  @doc ~s"""
  Start a worker/supervisor only if the condition is satisfied.
  The first argument is a function with arity 0 so it is lazily evaluated
  Example: Start a worker only if an ENV var is present
    start_if(fn -> {MySupervisor, []} end, fn -> System.get_env("ENV_VAR") end)
  """
  @spec start_if((() -> any), (() -> boolean)) :: nil | any
  def start_if(expr, condition) when is_function(condition, 0) and is_function(expr, 0) do
    if condition.() do
      expr.()
    end
  rescue
    error ->
      Logger.error("Caught error in start_if/2. Reason: #{Exception.message(error)}")

      reraise error, __STACKTRACE__
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
