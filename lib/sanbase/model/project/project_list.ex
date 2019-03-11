defmodule Sanbase.Model.Project.List do
  import Ecto.Query

  alias Sanbase.Repo

  alias Sanbase.Model.Project

  @preloads [
    :eth_addresses,
    :latest_coinmarketcap_data,
    icos: [ico_currencies: [:currency]]
  ]

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

  def slugs_by_ids(ids) do
    from(
      p in Project,
      where: p.id in ^ids and not is_nil(p.coinmarketcap_id),
      select: p.coinmarketcap_id
    )
    |> Repo.all()
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
end
