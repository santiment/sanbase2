defmodule Sanbase.Mix.Helper.ScheduleRescrapeHelpers do
  alias Sanbase.Project
  alias Sanbase.ExternalServices.Coinmarketcap.ScheduleRescrapePrice

  @doc ~s"""
  Schedule a rescrape in the [from, to] interval for all the projects that are
  scraped from coinmarketcap, or for the projects in `opts[:projects]`.
  The priority is set with `opts[:priority]` (:normal by default).

  Returns the list of {project_slug, error} for the rescrapes that could not be
  created, for example because the project already has an active rescrape.
  """
  def run(from, to, opts \\ []) do
    projects =
      Keyword.get(opts, :projects) ||
        Project.List.projects_with_source("coinmarketcap", include_hidden: true)

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
end
