defmodule Sanbase.Billing.BusinessClients.UsageTest do
  use Sanbase.DataCase, async: false

  @moduletag capture_log: true

  alias Sanbase.Billing.BusinessClients.Usage

  describe "active_days_two_windows/3" do
    test "the active days of the two windows, over API calls and web events" do
      test_pid = self()

      result =
        Sanbase.Mock.prepare_mock(Sanbase.ClickhouseRepo, :query, fn sql, args, _opts ->
          send(test_pid, {:query, sql, args})
          {:ok, %{rows: [[1, 12, 20], [2, 0, 3]]}}
        end)
        |> Sanbase.Mock.run_with_mocks(fn ->
          Usage.active_days_two_windows([1, 2, 3], 30, ~D[2026-11-10])
        end)

      # User 3 had no activity and is absent.
      assert result == {:ok, %{1 => {12, 20}, 2 => {0, 3}}}

      assert_receive {:query, sql, args}
      assert sql =~ "api_call_data"
      assert sql =~ "sanbase_user_events"
      assert sql =~ "auth_method IN ('apikey', 'jwt')"
      refute sql =~ "2026-"

      # Whole days, the last one included.
      assert args == %{
               "from" => ~U[2026-09-12 00:00:00Z],
               "middle" => ~U[2026-10-12 00:00:00Z],
               "until" => ~U[2026-11-11 00:00:00Z],
               "user_ids" => [1, 2, 3]
             }
    end

    test "no users, no query" do
      assert Usage.active_days_two_windows([], 30, ~D[2026-11-10]) == {:ok, %{}}
    end

    test "a failed query is an error, not a map of inactive users" do
      result =
        Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:error, "timeout"})
        |> Sanbase.Mock.run_with_mocks(fn ->
          Usage.active_days_two_windows([1], 30, ~D[2026-11-10])
        end)

      assert result == :error
    end
  end

  describe "last_api_call/3" do
    test "the last API key call per user, in one bounded, parameterized query" do
      until = ~U[2026-10-22 12:00:00Z]
      last = ~U[2026-10-20 08:30:00Z]
      test_pid = self()

      result =
        Sanbase.Mock.prepare_mock(Sanbase.ClickhouseRepo, :query, fn sql, args, _opts ->
          send(test_pid, {:query, sql, args})
          {:ok, %{rows: [[1, DateTime.to_unix(last)]]}}
        end)
        |> Sanbase.Mock.run_with_mocks(fn -> Usage.last_api_call([1, 2], until) end)

      assert result == %{1 => last}

      assert_receive {:query, sql, args}
      assert sql =~ "max(dt)"
      assert sql =~ "auth_method = 'apikey'"
      # The ids and the bounds are parameters, not interpolated.
      refute sql =~ "2026-"

      assert args == %{
               "from" => DateTime.add(until, -365, :day),
               "until" => until,
               "user_ids" => [1, 2]
             }
    end

    test "no users, no query" do
      assert Usage.last_api_call([], DateTime.utc_now()) == %{}
    end

    test "a failed query is an empty map" do
      result =
        Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:error, "timeout"})
        |> Sanbase.Mock.run_with_mocks(fn -> Usage.last_api_call([1], DateTime.utc_now()) end)

      assert result == %{}
    end
  end
end
