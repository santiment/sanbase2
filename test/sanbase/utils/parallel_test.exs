defmodule Sanbase.ParallelTest do
  use ExUnit.Case, async: false

  describe "map_or_error/3" do
    test "returns the results in order when every task succeeds" do
      assert {:ok, [2, 4, 6]} = Sanbase.Parallel.map_or_error([1, 2, 3], &{:ok, &1 * 2})
    end

    test "stops the remaining tasks after the first error" do
      test_pid = self()

      result =
        Sanbase.Parallel.map_or_error(
          [:fail, :a, :b],
          fn
            :fail ->
              {:error, :boom}

            x ->
              send(test_pid, {:started, x})
              {:ok, x}
          end,
          max_concurrency: 1
        )

      assert result == {:error, :boom}
      refute_received {:started, _}
    end

    test "a timed out task fails the whole call" do
      result =
        Sanbase.Parallel.map_or_error(
          [:slow, :fast],
          fn
            :slow -> Process.sleep(:infinity)
            x -> {:ok, x}
          end,
          timeout: 500
        )

      assert {:error, {:exit, :timeout}} = result
    end
  end

  describe "map/3 with on_timeout: :drop" do
    @tag capture_log: true
    test "drops timed out tasks" do
      result =
        Sanbase.Parallel.map(
          [:slow, :fast],
          fn
            :slow -> Process.sleep(:infinity)
            x -> x
          end,
          on_timeout: :drop,
          timeout: 500
        )

      assert result == [:fast]
    end

    @tag capture_log: true
    test "keeps exits that are not timeouts" do
      Process.flag(:trap_exit, true)

      result =
        Sanbase.Parallel.map(
          [:crash, :fast],
          fn
            :crash -> exit(:boom)
            x -> x
          end,
          on_timeout: :drop,
          timeout: 1_000
        )

      assert {:exit, {:crash, :boom}} in result
      assert :fast in result
    end
  end
end
