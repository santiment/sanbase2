defmodule Sanbase.Queries.RefreshWorkerDeterministicErrorsTest do
  @moduledoc ~s"""
  Reproduces SANBASE-BACKEND-PROD-G54:
  Oban.PerformError Sanbase.Queries.RefreshWorker failed with
  {:error, "Failed to refresh query_id=515 user_id=97409. Reason: [...] (ILLEGAL_PREWHERE)
  Storage View doesn't support PREWHERE."}

  The query text itself is invalid for ClickHouse, so the error is deterministic.
  The worker does not recognise ILLEGAL_PREWHERE as non-retryable, so:
    * every attempt (3/3) fails and is reported to Sentry
    * the next daily refresh stays scheduled, so this repeats forever.

  Deterministic ClickHouse errors should cancel the job (no retries, no Sentry
  event) and cancel the next scheduled refresh.
  """
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Queries
  alias Sanbase.Queries.RefreshWorker

  @illegal_prewhere_error "[9eaa0d5b-cb52-4be9-abbb-d845bd8cec59] (ILLEGAL_PREWHERE) " <>
                            "Storage View doesn't support PREWHERE."

  setup do
    user = insert(:user)

    {:ok, query} =
      Queries.create_query(
        %{sql_query_text: "SELECT * FROM some_view PREWHERE 1", sql_query_parameters: %{}},
        user.id
      )

    %{user: user, query: query}
  end

  defp job(query, user, attempt) do
    %Oban.Job{
      id: 1,
      attempt: attempt,
      max_attempts: 3,
      args: %{
        "query_id" => query.id,
        "user_id" => user.id,
        "next_refresh_in_seconds" => 86_400
      }
    }
  end

  defp mock_clickhouse_error() do
    Sanbase.Mock.prepare_mock(Sanbase.Queries, :run_query, fn _query, _user, _metadata, _opts ->
      {:error, @illegal_prewhere_error}
    end)
  end

  test "ILLEGAL_PREWHERE cancels the next scheduled refresh", %{query: query, user: user} do
    mock_clickhouse_error()
    |> Sanbase.Mock.run_with_mocks(fn ->
      RefreshWorker.perform(job(query, user, 1))

      assert [%Oban.Job{state: "cancelled"}] = scheduled_refresh_jobs()
    end)
  end

  test "ILLEGAL_PREWHERE cancels the job instead of erroring", %{query: query, user: user} do
    mock_clickhouse_error()
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert {:cancel, reason} = RefreshWorker.perform(job(query, user, 1))
      assert reason =~ "query_id=#{query.id}"
      assert reason =~ "ILLEGAL_PREWHERE"
    end)
  end

  defp scheduled_refresh_jobs() do
    from(job in Oban.Job, where: job.worker == "Sanbase.Queries.RefreshWorker")
    |> Sanbase.Repo.all()
  end
end
