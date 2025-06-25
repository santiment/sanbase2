defmodule Sanbase.GracefulShutdownTest do
  use ExUnit.Case, async: false
  require Logger

  alias Sanbase.GracefulShutdown

  setup do
    # Start the graceful shutdown process for testing
    {:ok, pid} = GracefulShutdown.start_link()

    on_exit(fn ->
      # Clean up after test
      if Process.alive?(pid) do
        GenServer.stop(pid, :normal)
      end
    end)

    {:ok, %{pid: pid}}
  end

  test "tracks request start and finish", %{pid: pid} do
    # Initially no active requests
    assert GracefulShutdown.get_active_requests_count() == 0

    # Start a request
    GracefulShutdown.request_started()
    assert GracefulShutdown.get_active_requests_count() == 1

    # Start another request
    GracefulShutdown.request_started()
    assert GracefulShutdown.get_active_requests_count() == 2

    # Finish first request
    GracefulShutdown.request_finished()
    assert GracefulShutdown.get_active_requests_count() == 1

    # Finish second request
    GracefulShutdown.request_finished()
    assert GracefulShutdown.get_active_requests_count() == 0
  end

  test "handles multiple concurrent requests", %{pid: pid} do
    # Simulate multiple concurrent requests
    tasks =
      for i <- 1..10 do
        Task.async(fn ->
          GracefulShutdown.request_started()
          # Simulate some work
          Process.sleep(10)
          GracefulShutdown.request_finished()
        end)
      end

    # Wait for all tasks to complete
    Enum.each(tasks, &Task.await/1)

    # All requests should be finished
    assert GracefulShutdown.get_active_requests_count() == 0
  end

  test "gracefully handles process termination during request tracking" do
    # Test that request tracking doesn't crash if the process is terminated
    assert GracefulShutdown.request_started() == :ok

    # Simulate process termination by stopping the GenServer
    GenServer.stop(GracefulShutdown, :normal)

    # These calls should not crash even though the process is gone
    assert GracefulShutdown.request_started() == :ok
    assert GracefulShutdown.request_finished() == :ok
    assert GracefulShutdown.get_active_requests_count() == 0
  end

  test "health endpoint integration" do
    # This test would require the full application to be running
    # In a real test environment, you'd start the application and
    # make actual HTTP requests to the /health endpoint

    # For now, just verify the function exists and returns a number
    count = GracefulShutdown.get_active_requests_count()
    assert is_integer(count)
    assert count >= 0
  end
end
