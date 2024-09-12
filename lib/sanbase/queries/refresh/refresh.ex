defmodule Sanbase.Queries.Refresh do
  alias Sanbase.Queries.Query
  alias Sanbase.Queries.QueryMetadata
  alias Sanbase.Queries.RefreshWorker
  alias Sanbase.Queries.RefreshSchedulerWorker
  alias Sanbase.Accounts.User

  @oban_conf_name :oban_web

  def schedule_refresh_all_user_queries(user_id) do
    data = RefreshSchedulerWorker.new(%{user_id: user_id}, scheduled_at: tomorrow_1_am())
    Oban.insert!(@oban_conf_name, data)
  end

  def refresh_all_user_queries(user_id) do
    queries = all_user_queries(user_id)

    Enum.each(queries, fn query ->
      schedule_refresh_query(query.id, user_id)
    end)
  end

  def schedule_refresh_query(query_id, user_id, next_refresh_in_seconds \\ 24 * 60 * 60) do
    data =
      RefreshWorker.new(%{
        user_id: user_id,
        query_id: query_id,
        next_refresh_in_seconds: next_refresh_in_seconds
      })

    Oban.insert!(@oban_conf_name, data)
  end

  def refresh_query(%Query{} = query, %User{} = user) do
    # Refresh by using the ReadOnly dynamic clickhouse repo
    Process.put(:queries_dynamic_repo, Sanbase.ClickhouseRepo.ReadOnly)

    query_metadata = QueryMetadata.from_refresh_job(user.id)

    # Don't store the execution details in the database. Also don't deduct credits from users for refreshing queries
    with {:ok, result} <-
           Sanbase.Queries.run_query(query, user, query_metadata, store_execution_details: false),
         {:ok, _} <- Sanbase.Queries.cache_query_execution(query.id, result, user.id),
         :ok <- refresh_query_dashboards_cache(result, user.id) do
      {:ok, result}
    end
  end

  def refresh_query(query_id, user_id) do
    {:ok, query} = Sanbase.Queries.get_query(query_id, user_id)
    user = Sanbase.Accounts.get_user!(user_id)
    refresh_query(query, user)
  end

  def refresh_query_dashboards_cache(query_result, user_id) do
    Sanbase.Dashboards.DashboardQueryMapping.dashboards_by_query_and_user(
      query_result.query_id,
      user_id
    )
    |> Sanbase.Repo.all()
    |> Enum.each(fn mapping ->
      Sanbase.Dashboards.cache_dashboard_query_execution(
        mapping.dashboard_id,
        _parameters_override_hash = nil,
        mapping.id,
        query_result,
        user_id
      )
    end)
  end

  def all_user_queries(user_id, page \\ 1, acc \\ []) do
    {:ok, queries} =
      Sanbase.Queries.get_user_queries(user_id, user_id, page: page, page_size: 100)

    case queries do
      [] -> acc
      _ -> all_user_queries(user_id, page + 1, acc ++ queries)
    end
  end

  defp tomorrow_1_am do
    # tomorrow 1AM after midnight
    Timex.now()
    |> Timex.beginning_of_day()
    |> Timex.shift(days: 1, hours: 1)
  end
end
