defmodule Sanbase.ExternalServices.RateLimiting.PriorityServerTest do
  use ExUnit.Case, async: true

  alias Sanbase.ExternalServices.RateLimiting.PriorityServer

  test "grants the requests by priority" do
    name = start_server(normal_every: 100)
    block(name)

    for priority <- [:low, :normal, :high, :low, :high] do
      spawn_waiter(name, priority)
    end

    assert grant_order(5) == [:high, :high, :normal, :low, :low]
  end

  test "the normal priority gets a reserved share" do
    name = start_server(normal_every: 2)
    block(name)

    for priority <- [:high, :high, :high, :normal, :normal] do
      spawn_waiter(name, priority)
    end

    assert grant_order(5) == [:high, :normal, :high, :normal, :high]
  end

  test "skips the waiters that are no longer alive" do
    name = start_server([])
    block(name)

    dead = spawn_waiter(name, :high)
    Process.exit(dead, :kill)
    spawn_waiter(name, :normal)

    assert grant_order(1) == [:normal]
  end

  test "respects the rate limit" do
    # Hammer uses fixed wall clock windows. A long window makes crossing a
    # window boundary during the test practically impossible.
    name = start_server(limit: 2, scale: :timer.hours(24))
    test_pid = self()

    for _ <- 1..3 do
      spawn(fn ->
        :ok = PriorityServer.wait(name, :normal)
        send(test_pid, :granted)
      end)
    end

    assert_receive :granted
    assert_receive :granted
    refute_receive :granted, 200
  end

  test "bypass grants immediately" do
    name = start_server(bypass: true, limit: 0)
    assert :ok = PriorityServer.wait(name, :low)
  end

  defp start_server(opts) do
    name = :"priority_server_test_#{System.unique_integer([:positive])}"

    opts =
      [scale: 60_000, limit: 1000, time_between_requests: 0, bypass: false]
      |> Keyword.merge(opts)

    start_supervised!(PriorityServer.child_spec(name, opts))
    name
  end

  # Block the server, so the waiters are queued before anything is granted
  defp block(name), do: :ok = PriorityServer.wait_until(name, DateTime.utc_now())

  defp spawn_waiter(name, priority) do
    test_pid = self()

    pid =
      spawn(fn ->
        :ok = PriorityServer.wait(name, priority)
        send(test_pid, {:granted, priority})
      end)

    # Make sure the waiter is enqueued before the next one
    wait_for_waiters(name, pid)
    pid
  end

  defp wait_for_waiters(name, pid) do
    state = :sys.get_state(name)

    enqueued? =
      Enum.any?(state.queues, fn {_, queue} ->
        Enum.any?(:queue.to_list(queue), &match?({^pid, _}, &1))
      end)

    if not enqueued?, do: wait_for_waiters(name, pid)
  end

  defp grant_order(count) do
    for _ <- 1..count do
      assert_receive {:granted, priority}, 3000
      priority
    end
  end
end
