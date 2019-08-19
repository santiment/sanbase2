defmodule Sanbase.Model.Project.List do
  @moduledoc ~s"""
  Provide functions for fetching different subsets of projects.

  Provided functions for getting a list of:
  - all projects
  - erc20 projects
  - currency projects
  - all/erc20/currency projects page ordered by rank
  - projects filtered by market segment
  """
  import Ecto.Query

  alias Sanbase.Repo

  alias Sanbase.Model.Project

  @preloads [:eth_addresses, :latest_coinmarketcap_data, :github_organizations]

  defguard is_valid_volume(volume) when is_number(volume) and volume >= 0

  @doc ~s"""
  Return all erc20 projects
  """
  def erc20_projects(min_volume \\ nil)

  def erc20_projects(min_volume) do
    erc20_projects_query(min_volume)
    |> order_by([p], p.name)
    |> Repo.all()
  end

  def erc20_projects_count(min_volume) do
    erc20_projects_query(min_volume)
    |> select([p], fragment("count(*)"))
    |> Repo.one()
  end

  defp erc20_projects_query(min_volume \\ nil)

  defp erc20_projects_query(nil) do
    from(
      p in projects_query(),
      join: infr in assoc(p, :infrastructure),
      where: not is_nil(p.main_contract_address) and infr.code == "ETH"
    )
  end

  defp erc20_projects_query(min_volume) when is_valid_volume(min_volume) do
    erc20_projects_query()
    |> order_by_rank_above_volume(min_volume)
  end

  @doc ~s"""
  Returns `page_size` number of projects from the `page` pages ordered by rank
  """
  def erc20_projects_page(page, page_size, min_volume \\ nil)

  def erc20_projects_page(page, page_size, min_volume) do
    erc20_projects_page_query(page, page_size, min_volume)
    |> Repo.all()
  end

  defp erc20_projects_page_query(page, page_size, nil) do
    erc20_projects_query()
    |> order_by_rank()
    |> page(page, page_size)
  end

  defp erc20_projects_page_query(page, page_size, min_volume) when is_valid_volume(min_volume) do
    erc20_projects_query()
    |> order_by_rank_above_volume(min_volume)
    |> page(page, page_size)
  end

  @doc ~s"""
  Return all currency projects.
  Classify as currency project everything except ERC20.
  """
  def currency_projects(min_volume \\ nil)

  def currency_projects(min_volume) do
    currency_projects_query(min_volume)
    |> order_by([p], p.name)
    |> Repo.all()
  end

  def currency_projects_count(min_volume) do
    currency_projects_query(min_volume)
    |> select([p], fragment("count(*)"))
    |> Repo.one()
  end

  defp currency_projects_query(min_volume \\ nil)

  defp currency_projects_query(nil) do
    from(
      p in projects_query(),
      join: infr in assoc(p, :infrastructure),
      where: is_nil(p.main_contract_address) or infr.code != "ETH"
    )
  end

  defp currency_projects_query(min_volume) when is_valid_volume(min_volume) do
    currency_projects_query()
    |> order_by_rank_above_volume(min_volume)
  end

  @doc ~s"""
  Returns `page_size` number of currency projects from the `page` pages.
  Classify as currency project everything except ERC20.
  """
  def currency_projects_page(page, page_size, min_volume \\ nil)

  def currency_projects_page(page, page_size, min_volume) do
    currency_projects_page_query(page, page_size, min_volume)
    |> Repo.all()
  end

  defp currency_projects_page_query(page, page_size, nil) do
    currency_projects_query()
    |> order_by_rank()
    |> page(page, page_size)
  end

  defp currency_projects_page_query(page, page_size, min_volume)
       when is_valid_volume(min_volume) do
    currency_projects_query()
    |> order_by_rank_above_volume(min_volume)
    |> page(page, page_size)
  end

  @doc ~s"""
  Return all projects
  """
  def projects(min_volume \\ nil)

  def projects(min_volume) do
    projects_query(min_volume)
    |> order_by([p], p.name)
    |> Repo.all()
  end

  def projects_count(min_volume) do
    projects_query(min_volume)
    |> select([p], fragment("count(*)"))
    |> Repo.one()
  end

  defp projects_query(min_volume \\ nil)

  defp projects_query(nil) do
    from(
      p in Project,
      where: not is_nil(p.coinmarketcap_id),
      preload: ^@preloads
    )
  end

  defp projects_query(min_volume) do
    projects_query()
    |> order_by_rank_above_volume(min_volume)
  end

  @doc ~s"""
  Returns `page_size` number of all projects from the `page` pages
  """
  def projects_page(page, page_size, min_volume \\ nil)

  def projects_page(page, page_size, min_volume) do
    projects_page_query(page, page_size, min_volume)
    |> Repo.all()
  end

  defp projects_page_query(page, page_size, nil) do
    projects_query()
    |> order_by_rank()
    |> page(page, page_size)
  end

  defp projects_page_query(page, page_size, min_volume) when is_valid_volume(min_volume) do
    projects_query()
    |> order_by_rank_above_volume(min_volume)
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

  defp order_by_rank_above_volume(query, min_volume) do
    from(
      p in query,
      join: latest_cmc in assoc(p, :latest_coinmarketcap_data),
      where: latest_cmc.volume_usd >= ^min_volume,
      order_by: latest_cmc.rank
    )
  end

  def projects_transparency() do
    projects_query()
    |> where([p], p.project_transparency)
    |> order_by([p], p.name)
    |> Repo.all()
  end

  def project_slugs_with_github_link() do
    from(p in Project,
      where: not is_nil(p.coinmarketcap_id) and not is_nil(p.github_link),
      select: p.coinmarketcap_id
    )
    |> Repo.all()
  end

  def slugs_by_field(values, field) do
    from(
      p in Project,
      where: field(p, ^field) in ^values and not is_nil(p.coinmarketcap_id),
      select: p.coinmarketcap_id
    )
    |> Repo.all()
  end

  def field_slug_map(values, field) do
    from(
      p in Project,
      where: field(p, ^field) in ^values and not is_nil(p.coinmarketcap_id),
      select: {field(p, ^field), p.coinmarketcap_id}
    )
    |> Repo.all()
    |> Map.new()
  end

  def slug_price_change_map() do
    from(p in Project,
      where: not is_nil(p.coinmarketcap_id),
      join: latest_cmc in assoc(p, :latest_coinmarketcap_data),
      select: {p.coinmarketcap_id, latest_cmc}
    )
    |> Repo.all()
    |> Enum.map(fn {slug, lcd} -> {slug, lcd} end)
    |> Map.new()
  end

  def by_market_segment(segment) when is_binary(segment) or is_list(segment) do
    segments = List.wrap(segment)

    projects_query()
    |> join(:inner, [p], m in assoc(p, :market_segment))
    |> where([_, m], m.name in ^segments)
    |> Repo.all()
  end

  def by_slugs(slugs) when is_list(slugs) do
    projects_query()
    |> where([p], p.coinmarketcap_id in ^slugs)
    |> Repo.all()
  end

  def by_field(values, field) when is_list(values) do
    projects_query()
    |> where([p], field(p, ^field) in ^values)
    |> Repo.all()
  end

  def by_any_of(values, fields) when is_list(values) and is_list(fields) do
    query =
      fields
      |> Enum.reduce(Project, fn field, q ->
        q |> or_where([p], field(p, ^field) in ^values)
      end)

    query
    |> Repo.all()
  end

  def by_name_ticker_slug(values) do
    values = List.wrap(values)

    from(p in projects_query(),
      where:
        fragment("lower(?)", p.name) in ^values or
          fragment("lower(?)", p.ticker) in ^values or
          fragment("lower(?)", p.coinmarketcap_id) in ^values
    )
    |> Repo.all()
  end

  def currently_trending_projects() do
    {:ok, trending_words} = Sanbase.SocialData.TrendingWords.get_currently_trending_words()

    trending_words_mapset =
      trending_words
      |> Enum.map(&String.downcase(&1.word))
      |> MapSet.new()

    Enum.reduce(projects(), [], fn project, acc ->
      if project_is_trending?(trending_words_mapset, project) do
        [project | acc]
      else
        acc
      end
    end)
  end

  def contract_info_map() do
    data =
      from(p in Project,
        where: not is_nil(p.coinmarketcap_id),
        select: {p.coinmarketcap_id, p.main_contract_address, p.token_decimals}
      )
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

  defp project_is_trending?(words_mapset, %Project{} = p) do
    # Project is trending if the intersection of [name, ticker, slug] and the trending
    # words is not empty
    empty? =
      MapSet.intersection(
        MapSet.new([p.ticker, p.name, p.coinmarketcap_id] |> Enum.map(&String.downcase/1)),
        words_mapset
      )
      |> Enum.empty?()

    !empty?
  end
end
