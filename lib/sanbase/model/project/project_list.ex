defmodule Sanbase.Model.Project.List do
  import Ecto.Query
  alias Sanbase.Repo

  alias Sanbase.Model.{Project, Infrastructure}

  @preloads [
    :eth_addresses,
    :latest_coinmarketcap_data,
    icos: [ico_currencies: [:currency]]
  ]

  @doc ~s"""
  Return all erc20 projects
  """
  def erc20_projects() do
    erc20_projects_query()
    |> order_by([p], p.name)
    |> Repo.all()
  end

  def erc20_projects_count() do
    erc20_projects_query()
    |> select([p], fragment("count(*)"))
    |> Repo.one()
  end

  defp erc20_projects_query() do
    from(
      p in Project,
      inner_join: infr in Infrastructure,
      on: p.infrastructure_id == infr.id,
      where:
        not is_nil(p.coinmarketcap_id) and not is_nil(p.main_contract_address) and
          infr.code == "ETH",
      preload: ^@preloads
    )
  end

  @doc ~s"""
  Returns `page_size` number of projects from the `page` pages
  """
  def erc20_projects_page(page, page_size) do
    from(
      p in Project,
      join: latest_cmc in assoc(p, :latest_coinmarketcap_data),
      inner_join: infr in Infrastructure,
      on: p.infrastructure_id == infr.id,
      where:
        not is_nil(p.coinmarketcap_id) and not is_nil(p.main_contract_address) and
          infr.code == "ETH",
      order_by: latest_cmc.rank,
      limit: ^page_size,
      offset: ^((page - 1) * page_size),
      preload: ^@preloads
    )
    |> Repo.all()
  end

  @doc ~s"""
  Return all currency projects.
  Classify as currency project everything except ERC20.
  """
  def currency_projects() do
    currency_projects =
      currency_projects_query()
      |> order_by([p], p.name)
      |> Repo.all()
  end

  def currency_projects_count() do
    currency_projects_query()
    |> select([p], fragment("count(*)"))
    |> Repo.one()
  end

  defp currency_projects_query() do
    from(p in Project,
      inner_join: infr in Infrastructure,
      on: p.infrastructure_id == infr.id,
      where:
        not is_nil(p.coinmarketcap_id) and (is_nil(p.main_contract_address) or infr.code != "ETH"),
      preload: ^@preloads
    )
  end

  @doc ~s"""
  Returns `page_size` number of currency projects from the `page` pages.
  Classify as currency project everything except ERC20.
  """
  def currency_projects_page(page, page_size) do
    from(
      p in Project,
      join: latest_cmc in assoc(p, :latest_coinmarketcap_data),
      inner_join: infr in Infrastructure,
      on: p.infrastructure_id == infr.id,
      where:
        not is_nil(p.coinmarketcap_id) and (is_nil(p.main_contract_address) or infr.code != "ETH"),
      order_by: latest_cmc.rank,
      limit: ^page_size,
      offset: ^((page - 1) * page_size),
      preload: ^@preloads
    )
    |> Repo.all()
  end

  @doc ~s"""
  Return all projects
  """
  def projects() do
    projects =
      projects_query()
      |> order_by([p], p.name)
      |> Repo.all()
  end

  def projects_count() do
    projects_query()
    |> select([p], fragment("count(*)"))
    |> Repo.one()
  end

  defp projects_query() do
    from(p in Project, where: not is_nil(p.coinmarketcap_id), preload: ^@preloads)
  end

  @doc ~s"""
  Returns `page_size` number of all projects from the `page` pages
  """
  def projects_page(page, page_size) do
    from(p in Project,
      join: latest_cmc in assoc(p, :latest_coinmarketcap_data),
      where: not is_nil(p.coinmarketcap_id),
      order_by: latest_cmc.rank,
      limit: ^page_size,
      offset: ^((page - 1) * page_size),
      preload: ^@preloads
    )
    |> Repo.all()
  end

  def projects_transparency() do
    projects_query()
    |> where([p], p.project_transparency)
    |> order_by([p], p.name)
    |> Repo.all()
  end
end
