defmodule Sanbase.Model.Project.List do
  @moduledoc ~s"""
  Provide functions for fetching different subsets of projects.

  Provided functions for getting a list of projects based on different filterings.

  ## Shared options
  Most of the functions accept a keyword options list as the last arguments.
  Currently two options are supported:
    - `:min_volume` - Filter out all projects with smaller trading volume
    - `:show_hidden_projects?` - Include the projects that are explictly
    hidden from lists. There are cases where a project needs to be removed
    from the public lists. But still those projects need to be included
    when fetched in a scraper so we do not lose data for them.
    Defaults to `false`.
  """
  import Ecto.Query

  alias Sanbase.Repo

  alias Sanbase.Model.Project

  @preloads [:eth_addresses, :latest_coinmarketcap_data, :github_organizations]

  defguard is_valid_volume(volume) when is_number(volume) and volume >= 0

  @doc ~s"""
  Return all projects ordered by name.
  Filtering out projects based on some conditions can be controled by the options.

  See the "Shared options" section at the module documentation for more options.
  """
  def projects(opts \\ [])

  def projects(opts) do
    projects_query(opts)
    |> order_by([p], p.name)
    |> Repo.all()
  end

  @doc ~s"""
  Return all erc20 projects ordered by name.
  Filtering out projects based on some conditions can be controled by the options.

  See the "Shared options" section at the module documentation for more options.
  """
  def erc20_projects(opts \\ [])

  def erc20_projects(opts) do
    erc20_projects_query(opts)
    |> order_by([p], p.name)
    |> Repo.all()
  end

  @doc ~s"""
  Return the list of the ERC20 projects. The options provided can
  Filtering out projects based on some conditions can be controled by the options.

  See the "Shared options" section at the module documentation for more options.
  """
  def erc20_projects_count(opts \\ [])

  def erc20_projects_count(opts) do
    erc20_projects_query(opts)
    |> select([p], fragment("count(*)"))
    |> Repo.one()
  end

  @doc ~s"""
  Returns `page_size` number of projects from the `page` pages ordered by rank
  """
  def erc20_projects_page(page, page_size, opts \\ [])

  def erc20_projects_page(page, page_size, opts) do
    erc20_projects_page_query(page, page_size, opts)
    |> Repo.all()
  end

  @doc ~s"""
  Return all currency projects.
  Classify as currency project everything except ERC20.
  """
  def currency_projects(opts \\ [])

  def currency_projects(opts) do
    currency_projects_query(opts)
    |> order_by([p], p.name)
    |> Repo.all()
  end

  def currency_projects_count(opts) do
    currency_projects_query(opts)
    |> select([p], fragment("count(*)"))
    |> Repo.one()
  end

  @doc ~s"""
  Returns `page_size` number of currency projects from the `page` pages.
  Classify as currency project everything except ERC20.
  """
  def currency_projects_page(page, page_size, opts \\ [])

  def currency_projects_page(page, page_size, opts) do
    currency_projects_page_query(page, page_size, opts)
    |> Repo.all()
  end

  @doc ~s"""
  Returns all projects with a given source in the source_slug_mappings table.

  For example using `coinmarketcap` source will return all projects that we
  have the coinamrketcap_id of.
  """
  def projects_with_source(source, opts \\ [])

  def projects_with_source(source, opts) do
    projects_query(opts)
    |> preload([:source_slug_mappings])
    |> Repo.all()
    |> Enum.filter(fn project -> source in Enum.map(project.source_slug_mappings, & &1.source) end)
  end

  def projects_count(opts) do
    projects_query(opts)
    |> select([p], fragment("count(*)"))
    |> Repo.one()
  end

  @doc ~s"""
  Returns `page_size` number of all projects from the `page` pages
  """
  def projects_page(page, page_size, opts \\ [])

  def projects_page(page, page_size, opts) do
    projects_page_query(page, page_size, opts)
    |> Repo.all()
  end

  def projects_transparency(opts \\ [])

  def projects_transparency(opts) do
    projects_query(opts)
    |> where([p], p.project_transparency)
    |> order_by([p], p.name)
    |> Repo.all()
  end

  def project_slugs_with_organization(opts \\ [])

  def project_slugs_with_organization(opts) do
    # explicitly remove preloads as they are not going to be used
    opts = Keyword.put(opts, :preload, false)

    projects_query(opts)
    |> join(:inner, [p], gl in Project.GithubOrganization)
    |> select([p, _gl], p.slug)
    |> distinct(true)
    |> Repo.all()
  end

  def slugs_by_field(values, field) do
    from(
      p in Project,
      where: field(p, ^field) in ^values and not is_nil(p.slug),
      select: p.slug
    )
    |> Repo.all()
  end

  def field_slug_map(values, field, opts \\ [])

  def field_slug_map(values, field, opts) do
    # explicitly remove preloads as they are not going to be used
    opts = Keyword.put(opts, :preload, false)

    projects_query(opts)
    |> where([p], field(p, ^field) in ^values)
    |> select([p], {field(p, ^field), p.slug})
    |> Repo.all()
    |> Map.new()
  end

  def select_field(field) do
    from(
      p in Project,
      where: not is_nil(field(p, ^field)),
      select: field(p, ^field)
    )
    |> Repo.all()
  end

  def slug_price_change_map(opts \\ [])

  def slug_price_change_map(opts) do
    # explicitly remove preloads as they are not going to be used
    opts = Keyword.put(opts, :preload, false)

    projects_query(opts)
    |> join(:inner, [p], latest_cmc in assoc(p, :latest_coinmarketcap_data))
    |> select([p, latest_cmc], {p.slug, latest_cmc})
    |> Repo.all()
    |> Map.new()
  end

  def by_market_segment(segment, opts \\ [])

  def by_market_segment(segment, opts) when is_binary(segment) or is_list(segment) do
    segments = List.wrap(segment)

    projects_query(opts)
    |> join(:inner, [p], m in assoc(p, :market_segment))
    |> where([_, m], m.name in ^segments)
    |> Repo.all()
  end

  @doc ~s"""
  Return a list of projects that have all of the provided market segments.
  Projects with only some of the segments are not returned.
  """
  def by_market_segments(segments, opts \\ [])

  def by_market_segments(segments, opts) when is_list(segments) do
    projects_query(opts)
    |> preload([:market_segments])
    |> join(:left, [p], ms in assoc(p, :market_segments))
    |> where([_p, ms], ms.name in ^segments)
    |> distinct(true)
    |> Repo.all()
    |> Enum.filter(fn
      %{market_segments: []} ->
        false

      %{market_segments: ms} ->
        # The query returns all projects that have at least one of the market
        # segments needed. We leave only those that have all segments
        segment_names = Enum.map(ms, & &1.name)
        Enum.all?(segments, &(&1 in segment_names))
    end)
  end

  def by_slugs(slugs, opts \\ [])

  def by_slugs(slugs, opts) when is_list(slugs) do
    projects_query(opts)
    |> where([p], p.slug in ^slugs)
    |> Repo.all()
  end

  def by_field(values, field, opts \\ [])

  def by_field(values, field, opts) when is_list(values) do
    projects_query(opts)
    |> where([p], field(p, ^field) in ^values)
    |> Repo.all()
  end

  def by_name_ticker_slug(values, opts \\ [])

  def by_name_ticker_slug(values, opts) do
    values = List.wrap(values)

    from(p in projects_query(opts),
      where:
        fragment("lower(?)", p.name) in ^values or
          fragment("lower(?)", p.ticker) in ^values or
          fragment("lower(?)", p.slug) in ^values
    )
    |> Repo.all()
  end

  def currently_trending_projects(opts \\ [])

  def currently_trending_projects(opts) do
    {:ok, trending_words} = Sanbase.SocialData.TrendingWords.get_currently_trending_words()

    trending_words
    |> Enum.map(&String.downcase(&1.word))
    |> by_name_ticker_slug(opts)
  end

  def contract_info_map(opts \\ [])

  def contract_info_map(opts) do
    # explicitly remove preloads as they are not going to be used
    opts = Keyword.put(opts, :preload, false)

    data =
      projects_query(opts)
      |> select([p], {p.slug, p.main_contract_address, p.token_decimals})
      |> Repo.all()

    {:ok, eth_contract, eth_decimals} = Project.contract_info_by_slug("ethereum")
    {:ok, btc_contract, btc_decimals} = Project.contract_info_by_slug("bitcoin")

    data =
      [
        {"ethereum", eth_contract, eth_decimals},
        {"bitcoin", btc_contract, btc_decimals}
      ] ++ data

    data
    |> Map.new(fn {slug, contract, decimals} -> {slug, {contract, decimals}} end)
  end

  # Private functions

  ## Fetch list of projects
  defp projects_query(opts) do
    from(
      p in Project,
      where: not is_nil(p.slug) and not is_nil(p.ticker)
    )
    |> maybe_preload(opts)
    |> maybe_show_hidden_projects?(opts)
    |> maybe_order_by_rank_above_volume(opts)
  end

  defp erc20_projects_query(opts) do
    from(
      p in projects_query(opts),
      join: infr in assoc(p, :infrastructure),
      where: not is_nil(p.main_contract_address) and infr.code == "ETH"
    )
    |> maybe_order_by_rank_above_volume(opts)
  end

  defp currency_projects_query(opts) do
    from(
      p in projects_query(opts),
      join: infr in assoc(p, :infrastructure),
      where: is_nil(p.main_contract_address) or infr.code != "ETH"
    )
  end

  ## Pagination queries

  defp projects_page_query(page, page_size, opts) do
    projects_query(opts)
    |> page(page, page_size)
  end

  defp erc20_projects_page_query(page, page_size, opts) do
    erc20_projects_query(opts)
    |> order_by_rank()
    |> page(page, page_size)
  end

  defp currency_projects_page_query(page, page_size, opts) do
    currency_projects_query(opts)
    |> order_by_rank()
    |> page(page, page_size)
  end

  defp page(query, page, page_size) do
    query
    |> offset(^((page - 1) * page_size))
    |> limit(^page_size)
  end

  defp order_by_rank(query) do
    from(
      p in query,
      join: latest_cmc in assoc(p, :latest_coinmarketcap_data),
      order_by: latest_cmc.rank
    )
  end

  defp maybe_order_by_rank_above_volume(query, opts) do
    case Keyword.get(opts, :min_volume, nil) do
      nil ->
        query

      min_volume ->
        from(
          p in query,
          join: latest_cmc in assoc(p, :latest_coinmarketcap_data),
          where: latest_cmc.volume_usd >= ^min_volume,
          order_by: latest_cmc.rank
        )
    end
  end

  defp maybe_show_hidden_projects?(query, opts) do
    case Keyword.get(opts, :show_hidden_projects?, true) do
      false ->
        query
        |> where([p], p.is_hidden_from_lists == false)

      true ->
        query
    end
  end

  defp maybe_preload(query, opts) do
    case Keyword.get(opts, :preload, true) do
      true -> query |> preload(^@preloads)
      false -> query
    end
  end
end
