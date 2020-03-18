defmodule Sanbase.Cache.RehydratingCache.Supervisor do
  use Supervisor
  alias Sanbase.Cache.RehydratingCache
  alias Sanbase.Cache.RehydratingCache.Store

  @name RehydratingCache.name()

  def child_spec(opts) do
    %{
      id: :"__rehydrating_cache_supervisor_#{@name}_id__",
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: :"__rehydrating_cache_supervisor_#{@name}__")
  end

  def init(_opts) do
    task_supervisor_name = Sanbase.Cache.RehydratingCache.TaskSupervisor

    children = [
      # ETS backed cache
      Supervisor.child_spec(
        {ConCache,
         [
           name: Store.name(@name),
           ttl_check_interval: :timer.seconds(15),
           global_ttl: :timer.hours(6),
           acquire_lock_timeout: 60_000
         ]},
        id: :"__rehydrating_cache_con_cache_#{@name}"
      ),

      # Task supervisor
      {Task.Supervisor, [name: task_supervisor_name]},

      # Worker - schedule get/run
      {Sanbase.Cache.RehydratingCache, task_supervisor: task_supervisor_name}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
