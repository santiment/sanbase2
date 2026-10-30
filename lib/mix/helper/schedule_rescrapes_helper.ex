defmodule Sanbase.Mix.Helper.ScheduleRescrapeHelpers do
  alias Sanbase.Project
  alias Sanbase.ExternalServices.Coinmarketcap.{ScheduleRescrapePrice, PriceScrapingProgress}

  @doc ~s"""
  Schedule a rescrape in the [from, to] interval for all the projects that are
  scraped from coinmarketcap (see `all_projects/0`), or for the projects in
  `opts[:projects]`.
  The priority is set with `opts[:priority]` (:normal by default).

  Returns the list of {project_slug, error} for the rescrapes that could not be
  created, for example because the project already has an active rescrape.
  """
  def run(from, to, opts \\ []) do
    projects = Keyword.get(opts, :projects) || all_projects()
    priority = Keyword.get(opts, :priority, :normal)

    Enum.flat_map(projects, fn p ->
      case ScheduleRescrapePrice.create(%{
             project_id: p.id,
             from: from,
             to: to,
             priority: priority
           }) do
        {:ok, _} -> []
        {:error, changeset} -> [{p.slug, Sanbase.Utils.ErrorHandling.changeset_errors(changeset)}]
      end
    end)
  end

  @doc ~s"""
  The projects with a coinmarketcap mapping that the regular scraper has
  already scraped. The rest cannot be rescraped, as they usually have no
  coinmarketcap integer id.
  """
  def all_projects() do
    scraped = PriceScrapingProgress.last_scraped_all_source("coinmarketcap")

    Project.List.projects_with_source("coinmarketcap", include_hidden: true)
    |> Enum.filter(&Map.has_key?(scraped, &1.slug))
  end
end
