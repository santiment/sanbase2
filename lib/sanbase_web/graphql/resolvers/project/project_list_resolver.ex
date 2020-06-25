defmodule SanbaseWeb.Graphql.Resolvers.ProjectListResolver do
  require Logger

  alias Sanbase.Model.Project

  @spec all_projects(any, map, any) :: {:ok, any}
  def all_projects(_parent, args, _resolution) do
    get_projects(args, :projects_page, :projects)
  end

  def all_erc20_projects(_root, args, _resolution) do
    get_projects(args, :erc20_projects_page, :erc20_projects)
  end

  def all_currency_projects(_root, args, _resolution) do
    get_projects(args, :currency_projects_page, :currency_projects)
  end

  defp get_projects(args, paged_fun, fun) do
    page = Map.get(args, :page)
    page_size = Map.get(args, :page_size)
    opts = Project.ListSelector.args_to_opts(args)

    projects =
      if page_arguments_valid?(page, page_size) do
        apply(Project.List, paged_fun, [page, page_size, opts])
      else
        apply(Project.List, fun, [opts])
      end

    {:ok, projects}
  end

  def all_projects_by_function(_root, %{function: function}, _resolution) do
    with {:ok, function} <- Sanbase.WatchlistFunction.cast(function),
         projects when is_list(projects) <- Sanbase.WatchlistFunction.evaluate(function) do
      {:ok, projects}
    end
  end

  def all_projects_by_ticker(_root, %{ticker: ticker}, _resolution) do
    {:ok, Project.List.projects_by_ticker(ticker)}
  end

  def projects_count(_root, args, _resolution) do
    opts = Project.ListSelector.args_to_opts(args)

    {:ok,
     %{
       erc20_projects_count: Project.List.erc20_projects_count(opts),
       currency_projects_count: Project.List.currency_projects_count(opts),
       projects_count: Project.List.projects_count(opts)
     }}
  end

  # Private functions

  defp page_arguments_valid?(page, page_size) when is_integer(page) and is_integer(page_size) do
    page > 0 and page_size > 0
  end

  defp page_arguments_valid?(_, _), do: false
end
