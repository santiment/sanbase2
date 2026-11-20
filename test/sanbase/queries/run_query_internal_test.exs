defmodule Sanbase.Queries.RunQueryInternalTest do
  @moduledoc """
  SECURITY_ANALYSIS.md C1: `run_query_internal/3` runs with the max access
  ClickHouse repo. That repo must not outlive the call, or every later
  ClickhouseRepo call in the same process keeps using it.
  """
  # Mock replaces modules globally, so these tests cannot be async.
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.ClickhouseRepo
  alias Sanbase.Queries

  @max_access_repo ClickhouseRepo.BusinessMaxUser

  setup do
    user = insert(:user)
    {:ok, query} = Queries.create_query(%{sql_query_text: "SELECT 1"}, user.id)

    %{query: query, query_metadata: Queries.QueryMetadata.from_local_dev(user.id)}
  end

  # Behaves like the real executor: it applies `:queries_dynamic_repo` as
  # Ecto's dynamic repo and reports which repo it ran with.
  defp run_with_executor(context, outcome) do
    test_pid = self()

    executor = fn _query, _metadata, _environment ->
      repo = Process.get(:queries_dynamic_repo)
      ClickhouseRepo.put_dynamic_repo(repo)
      send(test_pid, {:ran_with, repo})

      case outcome do
        :ok -> {:ok, %Queries.Executor.Result{rows: [[1]]}}
        :error -> {:error, "boom"}
        :raise -> raise "boom"
      end
    end

    Sanbase.Mock.prepare_mock(Queries.Executor, :run, executor)
    |> Sanbase.Mock.run_with_mocks(fn ->
      Queries.run_query_internal(context.query, context.query_metadata,
        store_execution_details: false
      )
    end)
  end

  for outcome <- [:ok, :error, :raise] do
    test "restores both repos after #{outcome}", context do
      default_repo = ClickhouseRepo.get_dynamic_repo()

      if unquote(outcome) == :raise do
        assert_raise RuntimeError, "boom", fn -> run_with_executor(context, :raise) end
      else
        run_with_executor(context, unquote(outcome))
      end

      assert_received {:ran_with, @max_access_repo}
      assert Process.get(:queries_dynamic_repo) == nil
      assert ClickhouseRepo.get_dynamic_repo() == default_repo
    end
  end

  test "restores the caller's own repo values", context do
    Process.put(:queries_dynamic_repo, ClickhouseRepo.FreeUser)
    ClickhouseRepo.put_dynamic_repo(ClickhouseRepo.ReadOnly)

    try do
      assert {:ok, _} = run_with_executor(context, :ok)
      assert_received {:ran_with, @max_access_repo}

      assert Process.get(:queries_dynamic_repo) == ClickhouseRepo.FreeUser
      assert ClickhouseRepo.get_dynamic_repo() == ClickhouseRepo.ReadOnly
    after
      Process.delete(:queries_dynamic_repo)
      ClickhouseRepo.put_dynamic_repo(ClickhouseRepo)
    end
  end
end
