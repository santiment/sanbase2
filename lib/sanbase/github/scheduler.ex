defmodule Sanbase.Github.Scheduler do
  alias Sanbase.Model.Project
  alias Sanbase.Github
  alias Sanbase.Prices

  # A dependency injection, so that we can test this module in isolation
  @worker Mockery.of("SanbaseWorkers.ImportGithubActivity")

  def schedule_scrape do
    Github.available_projects
    |> Enum.map(&get_initial_scrape_datetime/1)
    |> reduce_initial_scrape_datetime
    |> schedule_scrape_for_datetime(yesterday())
  end

  defp reduce_initial_scrape_datetime([]), do: nil

  defp reduce_initial_scrape_datetime(list), do: Enum.min_by(list, &DateTime.to_unix/1)

  defp schedule_scrape_for_datetime(nil, _last_datetime), do: :ok

  defp schedule_scrape_for_datetime(datetime, last_datetime) do
    case DateTime.compare(datetime, last_datetime) do
      :lt ->
        @worker.perform_async([archive_name_for(datetime)])

        datetime
        |> Timex.shift(hours: 1)
        |> schedule_scrape_for_datetime(last_datetime)
      _ -> :ok
    end
  end

  defp archive_name_for(datetime) do
    Timex.format!(datetime, "%Y-%m-%d-%-k", :strftime)
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
