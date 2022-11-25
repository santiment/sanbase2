defmodule Sanbase.Mix.Helper.ScheduleRescrapeHelpers do
  alias Sanbase.Project
  alias Sanbase.ExternalServices.Coinmarketcap.{ScheduleRescrapePrice, PriceScrapingProgress}

  def run(from, to, opts \\ []) do
    projects =
      Keyword.get(opts, :projects) ||
        Project.List.projects_with_source("coinmarketcap", include_hidden: true)

    last_scraped_map = PriceScrapingProgress.last_scraped_all_source("coinmarketcap")

    Enum.each(projects, fn p ->
      case Map.get(last_scraped_map, p.slug) do
        nil ->
          :ok

        last_scraped_dt ->
          %ScheduleRescrapePrice{}
          |> ScheduleRescrapePrice.changeset(%{
            project_id: p.id,
            from: from,
            to: to,
            original_last_updated: last_scraped_dt
          })
          |> Sanbase.Repo.insert!()
      end
    end)
  end
end
