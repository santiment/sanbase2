defmodule SanbaseWeb.Graphql.Resolvers.ProjectListResolver do
  alias Sanbase.Project
  alias SanbaseWeb.Graphql.Helpers.Utils

  @spec all_projects(any, map, any) :: {:ok, any}
  def all_projects(_parent, args, resolution) do
    get_projects(args, :projects_page, :projects, resolution)
  end

  def all_erc20_projects(_root, args, resolution) do
    get_projects(args, :erc20_projects_page, :erc20_projects, resolution)
  end

  def all_currency_projects(_root, args, resolution) do
    get_projects(args, :currency_projects_page, :currency_projects, resolution)
  end

  defp get_projects(args, paged_fun, fun, resolution) do
    with {:ok, opts} <- Project.ListSelector.args_to_opts(args, selector_opts(resolution)) do
      page = Map.get(args, :page)
      page_size = Map.get(args, :page_size)

      projects =
        if page_arguments_valid?(page, page_size) do
          apply(Project.List, paged_fun, [page, page_size, opts])
        else
          apply(Project.List, fun, [opts])
        end

      projects = Enum.uniq_by(projects, & &1.id)

      {:ok, projects}
    end
  end

  def all_projects_by_function(_root, %{function: function}, resolution) do
    with {:ok, function} <- Sanbase.WatchlistFunction.cast(function),
         {:ok, data} <- Sanbase.WatchlistFunction.evaluate(function, selector_opts(resolution)) do
      %{projects: projects, total_projects_count: total_projects_count} = data

      projects = Enum.uniq_by(projects, & &1.id)

      {:ok,
       %{
         projects: projects,
         stats: %{projects_count: total_projects_count}
       }}
    else
      error -> error
    end
  end

  def all_projects_by_function(_root, _args, _resolution) do
    {:error, "Invalid arguments provided to all_projects_by_function"}
  end

  def all_projects_by_ticker(_root, %{ticker: ticker}, _resolution) do
    projects = Project.List.projects_by_ticker(ticker) |> Enum.uniq_by(& &1.id)

    {:ok, projects}
  end

  def projects_count(_root, args, resolution) do
    with {:ok, opts} <- Project.ListSelector.args_to_opts(args, selector_opts(resolution)) do
      # Remove ordered_slugs from opts in case we need only the count
      opts = Keyword.replace(opts, :ordered_slugs, nil)

      {:ok,
       %{
         erc20_projects_count: Project.List.erc20_projects_count(opts),
         currency_projects_count: Project.List.currency_projects_count(opts),
         projects_count: Project.List.projects_count(opts)
       }}
    end
  end

  # Private functions

  # Watchlists in the base projects are resolved only if they are public or owned by
  # the current user.
  defp selector_opts(resolution), do: [user_id: Utils.resolution_to_user_id_or_nil(resolution)]

  defp page_arguments_valid?(page, page_size) when is_integer(page) and is_integer(page_size) do
    page > 0 and page_size > 0
  end

  defp page_arguments_valid?(_, _), do: false
end
