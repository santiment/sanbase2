defmodule SanbaseWeb.SuggestLiveHelpers do
  @moduledoc """
  Shared helpers for LiveViews that suggest changes (ecosystems, GitHub organizations, etc.).
  """

  @doc """
  Filter and sort projects by search string (name, ticker, slug).
  Returns all projects when search is empty, otherwise filters by match and sorts by Jaro distance.
  """
  @spec filter_projects_by_search([map()], String.t()) :: [map()]
  def filter_projects_by_search(projects, search) when is_binary(search) do
    search = search |> String.downcase() |> String.trim()

    case search do
      "" ->
        projects

      _ ->
        projects
        |> Enum.filter(fn p ->
          String.downcase(p.name) =~ search or String.downcase(p.ticker) =~ search or
            String.downcase(p.slug) =~ search
        end)
        |> Enum.sort_by(
          fn p -> String.jaro_distance(String.downcase(p.name), search) end,
          :desc
        )
    end
  end
end
