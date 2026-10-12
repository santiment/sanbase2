defmodule Sanbase.Queries.RefreshWorkerTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Queries
  alias Sanbase.Queries.RefreshWorker

  test "the error identifies the offending query" do
    user = insert(:user)

    {:ok, query} =
      Queries.create_query(
        %{
          sql_query_text: "SELECT * FROM metrics WHERE slug = {{asset1}}",
          sql_query_parameters: %{}
        },
        user.id
      )

    job = %Oban.Job{
      id: 1,
      attempt: 2,
      max_attempts: 3,
      args: %{"query_id" => query.id, "user_id" => user.id}
    }

    assert {:error, error} = RefreshWorker.perform(job)

    assert error =~ "Failed to refresh query_id=#{query.id} user_id=#{user.id}"
    assert error =~ "Template keys missing from the parameters: {{asset1}}"

    assert %{tags: tags} = Sentry.Context.get_all()
    assert tags[:oban_query_id] == to_string(query.id)
    assert tags[:oban_user_id] == to_string(user.id)
  end

  test "missing query does not raise, the job is cancelled and identifies the query id" do
    user = insert(:user)

    job = %Oban.Job{
      id: 1,
      attempt: 2,
      max_attempts: 3,
      args: %{"query_id" => 0, "user_id" => user.id}
    }

    assert {:cancel, error} = RefreshWorker.perform(job)

    assert error =~ "Failed to refresh query_id=0 user_id=#{user.id}"
    assert error =~ "Query does not exist or you don't have access to it."
  end

  test "missing query cancels the next scheduled refresh" do
    user = insert(:user)

    job = %Oban.Job{
      id: 1,
      attempt: 1,
      max_attempts: 3,
      args: %{"query_id" => 0, "user_id" => user.id}
    }

    assert {:cancel, error} = RefreshWorker.perform(job)

    assert error =~ "Failed to refresh query_id=0 user_id=#{user.id}"
    assert error =~ "Query does not exist or you don't have access to it."

    assert [%Oban.Job{state: "cancelled"}] = scheduled_refresh_jobs()
  end

  test "an error the query owner can fix keeps the next scheduled refresh" do
    user = insert(:user)

    {:ok, query} =
      Queries.create_query(
        %{
          sql_query_text: "SELECT * FROM metrics WHERE slug = {{asset1}}",
          sql_query_parameters: %{}
        },
        user.id
      )

    job = %Oban.Job{
      id: 1,
      attempt: 1,
      max_attempts: 3,
      args: %{"query_id" => query.id, "user_id" => user.id}
    }

    assert {:error, error} = RefreshWorker.perform(job)

    assert error =~ "Template keys missing from the parameters: {{asset1}}"

    assert [%Oban.Job{state: "scheduled"}] = scheduled_refresh_jobs()
  end

  for error <- [
        "(TIMEOUT_EXCEEDED) Timeout exceeded: elapsed 85 seconds",
        "(MEMORY_LIMIT_EXCEEDED) Memory limit (total) exceeded: would use 56.00 GiB",
        "(MEMORY_LIMIT_EXCEEDED) (total) memory limit exceeded: would use 56.00 GiB",
        "(MEMORY_LIMIT_EXCEEDED) Memory limit (for user) exceeded: would use 20.00 GiB"
      ] do
    test "the transient ClickHouse error #{error} is retried and keeps the next scheduled refresh" do
      job = refresh_job()

      mock_run_query({:error, "[9eaa0d5b] " <> unquote(error)})
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:error, error} = RefreshWorker.perform(job)
        assert error =~ unquote(error)

        assert [%Oban.Job{state: "scheduled"}] = scheduled_refresh_jobs()
      end)
    end
  end

  for error <- [
        "(ILLEGAL_PREWHERE) Storage View doesn't support PREWHERE.",
        "(MEMORY_LIMIT_EXCEEDED) Memory limit (for query) exceeded: would use 9.31 GiB",
        "(MEMORY_LIMIT_EXCEEDED) Query memory limit exceeded: would use 9.31 GiB"
      ] do
    test "the deterministic ClickHouse error #{error} cancels the job and the next scheduled refresh" do
      job = refresh_job()

      mock_run_query({:error, "[9eaa0d5b] " <> unquote(error)})
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:cancel, error} = RefreshWorker.perform(job)
        assert error =~ "query_id=#{job.args["query_id"]}"
        assert error =~ unquote(error)

        assert [%Oban.Job{state: "cancelled"}] = scheduled_refresh_jobs()
      end)
    end
  end

  defp refresh_job() do
    user = insert(:user)

    {:ok, query} =
      Queries.create_query(%{sql_query_text: "SELECT 1", sql_query_parameters: %{}}, user.id)

    %Oban.Job{
      id: 1,
      attempt: 1,
      max_attempts: 3,
      args: %{"query_id" => query.id, "user_id" => user.id}
    }
  end

  defp mock_run_query(result) do
    Sanbase.Mock.prepare_mock(Sanbase.Queries, :run_query, fn _query, _user, _metadata, _opts ->
      result
    end)
  end

  defp scheduled_refresh_jobs() do
    from(job in Oban.Job, where: job.worker == "Sanbase.Queries.RefreshWorker")
    |> Sanbase.Repo.all()
  end
end
