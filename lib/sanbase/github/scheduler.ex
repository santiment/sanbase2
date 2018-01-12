defmodule Sanbase.Github.Scheduler do
  alias Sanbase.Model.Project
  alias Sanbase.Github
  alias Sanbase.Prices
  alias Sanbase.Repo

  require Logger

  # A dependency injection, so that we can test this module in isolation
  @worker Mockery.of("SanbaseWorkers.ImportGithubActivity")

  def schedule_scrape do
    available_projects = Github.available_projects

    initial_scrape_datetime = available_projects
    |> log_scheduler_info
    |> Enum.map(&get_initial_scrape_datetime/1)
    |> Enum.reject(&is_nil/1)
    |> reduce_initial_scrape_datetime()

    schedule_scrape_for_datetime(initial_scrape_datetime, available_projects, yesterday())
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

  defp schedule_scrape_for_datetime(current_datetime, projects, last_datetime) do
    case DateTime.compare(current_datetime, last_datetime) do
      :lt ->
        need_to_scrape = projects
        |> Enum.any?(&need_to_scrape_project?(&1, current_datetime))

        if need_to_scrape do
          archive_name = archive_name_for(current_datetime)

          @worker.perform_async([archive_name])
        end

        current_datetime
        |> Timex.shift(hours: 1)
        |> schedule_scrape_for_datetime(projects, last_datetime)
      _ -> :ok
    end
  end

  defp need_to_scrape_project?(%Project{id: id, name: name}, datetime) do
    archive_name = archive_name_for(datetime)

    !Repo.get_by(Github.ProcessedGithubArchive, project_id: id, archive: archive_name)
  end

  defp get_initial_scrape_datetime(%Project{ticker: ticker}) do
    if Github.Store.first_activity_datetime(ticker) do
      Github.Store.last_activity_datetime(ticker)
    else
      Prices.Store.first_price_datetime(ticker <> "_USD")
    end
  end

  defp yesterday do
    Timex.now()
    |> Timex.shift(days: -1)
    |> Timex.end_of_day()
    |> Timex.to_datetime
  end
end
