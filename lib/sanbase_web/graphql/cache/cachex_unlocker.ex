defmodule SanbaseWeb.Graphql.CachexProvider.Unlocker do
  @moduledoc ~s"""
  Module that makes sure that locks acquired during get_or_store locking in
  the Cachex provider.

  When locks are acquired, a process is spawned that unlocks the lock in case
  something wrong does with the process that obtained it. If the process finishes
  fast without issues it will kill this process.
  """

  use GenServer

  def start(opts) do
    GenServer.start(__MODULE__, opts)
  end

  def init(opts) do
    max_lock_acquired_time_ms = Keyword.fetch!(opts, :max_lock_acquired_time_ms)
    # If the process that started the Unlocker terminates before sending the unlock_after
    # message this process will live forever. Because of this schedule a termination after
    # at least 2 `max_lock_acquired_time_ms` epochs has passed. Two are needed so it waits
    # both the lock obtaining time (up to ~55-60 seconds) and the actual lock holding time
    Process.send_after(self(), :self_terminate, 2 * max_lock_acquired_time_ms + 1000)
    {:ok, %{max_lock_acquired_time_ms: max_lock_acquired_time_ms}}
  end

  def handle_cast({:unlock_after, unlock_fun}, state) do
    Process.send_after(self(), {:unlock_lock, unlock_fun}, state[:max_lock_acquired_time_ms])
    {:noreply, state}
  end

  def handle_cast(:stop, state) do
    {:stop, :normal, state}
  end

  def handle_info({:unlock_lock, unlock_fun}, state) do
    unlock_fun.()
    {:noreply, state}
  end

  def handle_info(:self_terminate, state) do
    {:stop, :normal, state}
  end

  def terminate(_reason, _state) do
    :normal
  end
end
