defmodule Sanbase.Github.Scheduler do
  alias Sanbase.Model.Project
  alias Sanbase.Github
  alias Sanbase.Prices
  alias Sanbase.Repo

  require Logger

  import Ecto.Query

  # A dependency injection, so that we can test this module in isolation
  @worker Mockery.of("SanbaseWorkers.ImportGithubActivity")

  def schedule_scrape do
    available_projects = Github.available_projects

    processed_archives = available_projects
    |> fetch_processed_archives()

    available_projects
    |> log_scheduler_info
    |> Enum.map(&get_initial_scrape_datetime/1)
    |> Enum.reject(&is_nil/1)
    |> reduce_initial_scrape_datetime()
    |> schedule_scrape_for_datetime(yesterday(), processed_archives)
  end

  def archive_name_for(datetime) do
    Timex.format!(datetime, "%Y-%m-%d-%-k", :strftime)
  end

  defp log_scheduler_info(projects) do
    project_names = projects
    |> Enum.map(&(&1.name))

    Logger.info("Scheduling github activity scraping for projects #{inspect(project_names)}")

    projects
  end

  defp reduce_initial_scrape_datetime([]), do: nil

  defp reduce_initial_scrape_datetime(list), do: Enum.min_by(list, &DateTime.to_unix/1)

  defp schedule_scrape_for_datetime(nil, _last_datetime, _processed_archives), do: :ok

  defp schedule_scrape_for_datetime(datetime, last_datetime, processed_archives) do
    case DateTime.compare(datetime, last_datetime) do
      :lt ->
        archive_name = archive_name_for(datetime)

        unless MapSet.member?(processed_archives, archive_name) do
          @worker.perform_async([archive_name])
        end

        datetime
        |> Timex.shift(hours: 1)
        |> schedule_scrape_for_datetime(last_datetime, processed_archives)
      _ -> :ok
    end
  end

  defp get_initial_scrape_datetime(%Project{ticker: ticker}) do
    if Github.Store.first_activity_datetime(ticker) do
      Github.Store.last_activity_datetime(ticker)
    else
      Prices.Store.first_price_datetime(ticker <> "_USD")
    end
  end

  defp fetch_processed_archives(projects) do
    project_ids = projects
    |> Enum.map(&(&1.id))

    Github.ProcessedGithubArchive
    |> where([p], p.project_id in ^project_ids)
    |> group_by(:archive)
    |> having([p], count(p.project_id) == ^(length(project_ids)))
    |> select([:archive])
    |> Repo.all
    |> Enum.map(&(&1.archive))
    |> MapSet.new
  end

  defp yesterday do
    Timex.now()
    |> Timex.shift(days: -1)
    |> Timex.end_of_day()
    |> Timex.to_datetime
  end
end
