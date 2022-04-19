defmodule Sanbase.Model.Project.List do
  @preloads [
    :eth_addresses,
    :latest_coinmarketcap_data,
    :github_organizations,
    :contract_addresses
  ]

  @moduledoc ~s"""
  Provide functions for fetching different subsets of projects.

  Provided functions for getting a list of projects based on different filterings.

  ## Shared options
  Most of the functions accept a keyword options list as the last arguments.
  Currently following options are supported:
    - `:preload?` (boolean) - Do or do not preload associations. Control the list
       of associations to be preloaded with `:preload`
    - `:preload` (list) - A list of preloads if `:preload?` is true.
       Defaults to `#{inspect(@preloads)}
    - `:min_volume` (number) - Filter out all projects with smaller trading volume
    - `:include_hidden` (boolean) - Include the projects that are explictly
    hidden from lists. There are cases where a project needs to be removed
    from the public lists. But still those projects need to be included
    when fetched in a scraper so we do not lose data for them.
    Defaults to `false`.
  """
  import Ecto.Query

  alias Sanbase.Repo

  alias Sanbase.Model.Project

  defguard is_valid_volume(volume) when is_number(volume) and volume >= 0

  @doc ~s"""
  Return all projects ordered by name.
  Filtering out projects based on some conditions can be controled by the options.

  See the "Shared options" section at the module documentation for more options.
  """
  def projects(opts \\ [])

  def projects(opts) do
    projects_query(opts)
    |> Repo.all()
  end

  def projects_slugs(opts \\ [])

  def projects_slugs(opts) do
    opts = Keyword.put(opts, :preload?, false)

    projects_query(opts)
    |> select([p], p.slug)
    |> Repo.all()
  end

  def hidden_projects_slugs() do
    from(p in Project,
      where: p.is_hidden == true,
      select: p.slug
    )
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
    |> Repo.all()
  end

  def erc20_projects_slugs(opts \\ [])

  def erc20_projects_slugs(opts) do
    opts = Keyword.put(opts, :preload?, false)

    erc20_projects_query(opts)
    |> select([p], p.slug)
    |> Repo.all()
  end

  @doc ~s"""
  Return the list of the ERC20 projects. The options provided can
  Filtering out projects based on some conditions can be controled by the options.

  See the "Shared options" section at the module documentation for more options.
  """
  def erc20_projects_count(opts \\ [])

  def erc20_projects_count(opts) do
    opts = Keyword.put(opts, :preload?, false)

    erc20_projects_query(opts)
    |> select([p], fragment("count(*)"))
    |> Repo.one()
  end

  @doc ~s"""
  Returns `page_size` number of projects from the `page` pages ordered by rank.
  Filtering out projects based on some conditions can be controled by the options.

  See the "Shared options" section at the module documentation for more options.
  """
  def erc20_projects_page(page, page_size, opts \\ [])

  def erc20_projects_page(page, page_size, opts) do
    erc20_projects_page_query(page, page_size, opts)
    |> Repo.all()
  end

  @doc ~s"""
  Returns all currency projects. Classify as currency project everything except ERC20.
  Filtering out projects based on some conditions can be controled by the options.

  See the "Shared options" section at the module documentation for more options.
  """
  def currency_projects(opts \\ [])

  def currency_projects(opts) do
    currency_projects_query(opts)
    |> Repo.all()
  end

  def currency_projects_slugs(opts) do
    currency_projects_query(opts)
    |> select([p], p.slug)
    |> Repo.all()
  end

  @doc ~s"""
  Returns the count of the currency projects.
  Filtering out projects based on some conditions can be controled by the options.

  See the "Shared options" section at the module documentation for more options.
  """
  def currency_projects_count(opts \\ [])

  def currency_projects_count(opts) do
    opts = Keyword.put(opts, :preload?, false)

    currency_projects_query(opts)
    |> select([p], fragment("count(*)"))
    |> Repo.one()
  end

  @doc ~s"""
  Returns `page_size` number of currency projects from the `page` pages.
  Classify as currency project everything except ERC20.
  Filtering out projects based on some conditions can be controled by the options.

  See the "Shared options" section at the module documentation for more options.
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
  Filtering out projects based on some conditions can be controled by the options.

  See the "Shared options" section at the module documentation for more options.
  """
  def projects_with_source(source, opts \\ [])

  def projects_with_source(source, opts) do
    projects_query(opts)
    |> preload([:source_slug_mappings])
    |> Repo.all()
    |> Enum.filter(fn project -> source in Enum.map(project.source_slug_mappings, & &1.source) end)
  end

  def projects_count(opts \\ [])

  def projects_count(opts) do
    opts = Keyword.put(opts, :preload?, false)

    projects_query(opts)
    |> select([p], fragment("count(*)"))
    |> Repo.one()
  end

  @doc ~s"""
  Returns `page_size` number of all projects from the `page` pages.
  Filtering out projects based on some conditions can be controled by the options.

  See the "Shared options" section at the module documentation for more options.
  """
  def projects_page(page, page_size, opts \\ [])

  def projects_page(page, page_size, opts) do
    projects_page_query(page, page_size, opts)
    |> Repo.all()
  end

  def projects_by_ticker(ticker, opts \\ []) do
    projects_query(opts)
    |> where([p], p.ticker == ^ticker)
    |> Repo.all()
  end

  def slugs_by_infrastructure(infrastructures, opts \\ []) when is_list(infrastructures) do
    # explicitly remove preloads as they are not going to be used
    opts = Keyword.put(opts, :preload?, false)

    # If the infrastructure is `own` then use the ticker as infrastructure
    from(
      p in projects_query(opts),
      left_join: infr in assoc(p, :infrastructure),
      where:
        infr.code in ^infrastructures or
          (fragment("lower(?)", infr.code) == "own" and p.ticker in ^infrastructures),
      select: p.slug
    )
    |> Repo.all()
  end

  @doc ~s"""
  Returns all slugs of the projects that have one or more github organizations
  Filtering out projects based on some conditions can be controled by the options.

  See the "Shared options" section at the module documentation for more options.
  """
  def slugs_with_github_organization(opts \\ [])

  def slugs_with_github_organization(opts) do
    # explicitly remove preloads as they are not going to be used
    opts = Keyword.put(opts, :preload?, false)

    projects_query(opts)
    |> join(:inner, [p], gl in Project.GithubOrganization)
    |> select([p], p.slug)
    |> distinct(true)
    |> Repo.all()
  end

  def github_organizations_by_slug(slug_or_slugs, opts \\ [])

  def github_organizations_by_slug(slug_or_slugs, opts) do
    slugs = List.wrap(slug_or_slugs)
    opts = Keyword.put(opts, :preload?, false)

    projects_query(opts)
    |> where([p], p.slug in ^slugs)
    |> join(:left, [p], gl in Project.GithubOrganization, on: p.id == gl.project_id)
    |> select([p, gl], {p.slug, gl.organization})
    |> distinct(true)
    |> Repo.all()
    |> Enum.reduce(%{}, fn
      {slug, nil}, acc -> Map.update(acc, slug, [], & &1)
      {slug, org}, acc -> Map.update(acc, slug, [org], &[org | &1])
    end)
  end

  @doc ~s"""
  Returns all slugs of projects whose `field` has any of the values
  provided in `values`
  Filtering out projects based on some conditions can be controled by the options.

  See the "Shared options" section at the module documentation for more options.
  """
  def slugs_by_field(values, field, opts \\ [])

  def slugs_by_field(values, field, opts) do
    # explicitly remove preloads as they are not going to be used
    opts = Keyword.put(opts, :preload?, false)

    projects_query(opts)
    |> where([p], field(p, ^field) in ^values)
    |> select([p], p.slug)
    |> Repo.all()
  end

  @doc ~s"""
  Returns a map where the `field` is the key and the slug is the value
  Filtering out projects based on some conditions can be controled by the options.

  See the "Shared options" section at the module documentation for more options.
  """
  def field_slug_map(values, field, opts \\ [])

  def field_slug_map(values, field, opts) do
    # explicitly remove preloads as they are not going to be used
    opts = Keyword.put(opts, :preload?, false)

    projects_query(opts)
    |> where([p], field(p, ^field) in ^values)
    |> select([p], {field(p, ^field), p.slug})
    |> Repo.all()
    |> Map.new()
  end

  def projects_by_non_null_field(field, opts \\ [])

  def projects_by_non_null_field(field, opts) do
    # explicitly remove preloads as they are not going to be used
    opts = Keyword.put(opts, :preload?, false)

    projects_query(opts)
    |> where([p], not is_nil(field(p, ^field)))
    |> Repo.all()
  end

  @doc ~s"""
  Returns a list of all `field` values which are not nil
  Filtering out projects based on some conditions can be controled by the options.

  See the "Shared options" section at the module documentation for more options.
  """
  def select_field(field, opts \\ [])

  def select_field(field, opts) do
    # explicitly remove preloads as they are not going to be used
    opts = Keyword.put(opts, :preload?, false)

    projects_query(opts)
    |> where([p], not is_nil(field(p, ^field)))
    |> select([p], field(p, ^field))
    |> Repo.all()
  end

  @doc ~s"""
  Returns a map where the slug is the key and the latest coinmarketcap data
  map is the value.
  Filtering out projects based on some conditions can be controled by the options.

  See the "Shared options" section at the module documentation for more options.
  """
  def slug_price_change_map(opts \\ [])

  def slug_price_change_map(opts) do
    # explicitly remove preloads as they are not going to be used
    opts = Keyword.put(opts, :preload?, false)

    from(
      p in projects_query(opts),
      inner_join: latest_cmc in assoc(p, :latest_coinmarketcap_data),
      select: {p.slug, latest_cmc}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc ~s"""
  Returns all projects for which at least one of their market segments is in
  the list `segments`.
  Filtering out projects based on some conditions can be controled by the options.

  See the "Shared options" section at the module documentation for more options.
  """
  def by_market_segment_any_of(segments, opts \\ [])

  def by_market_segment_any_of(segments, opts)
      when is_binary(segments) or is_list(segments) do
    segments = List.wrap(segments)

    from(
      p in projects_query(opts),
      preload: [:market_segments],
      left_join: ms in assoc(p, :market_segments),
      where: ms.name in ^segments,
      distinct: true
    )
    |> Repo.all()
  end

  @doc ~s"""
  Return a list of projects that have all of the provided market segments.
  Projects with only some of the segments are not returned.
  Filtering out projects based on some conditions can be controled by the options.

  See the "Shared options" section at the module documentation for more options.
  """
  def by_market_segment_all_of(segments, opts \\ [])

  def by_market_segment_all_of(segments, opts) when is_list(segments) do
    from(
      p in projects_query(opts),
      preload: [:market_segments],
      left_join: ms in assoc(p, :market_segments),
      where: ms.name in ^segments,
      distinct: true
    )
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

  @doc ~s"""
  Return a list of projects that have a slug in the list of `slugs`
  Filtering out projects based on some conditions can be controled by the options.

  See the "Shared options" section at the module documentation for more options.
  """
  def by_slugs(slugs, opts \\ [])

  def by_slugs(slugs, opts) when is_list(slugs) do
    projects_query(opts)
    |> where([p], p.slug in ^slugs)
    |> Repo.all()
  end

  @doc ~s"""
  Return a list of project ids that have a slug in the list of `slugs`
  Filtering out projects based on some conditions can be controled by the options.

  See the "Shared options" section at the module documentation for more options.
  """
  def ids_by_slugs(slugs, opts \\ []) do
    opts = Keyword.put(opts, :preload?, false)

    projects_query(opts)
    |> where([p], p.slug in ^slugs)
    |> select([p], p.id)
    |> Repo.all()
  end

  @doc ~s"""
  Return a list of projects that a `field` value in the list of `values`.
  Filtering out projects based on some conditions can be controled by the options.

  See the "Shared options" section at the module documentation for more options.
  """
  def by_field(values, field, opts \\ [])

  # NOTE: This should be handled in more places. Ultimate solution would be to use
  # the citext type for such fields
  @case_insensitive_fields [:main_contract_address]
  def by_field(values, field, opts) when is_list(values) and field in @case_insensitive_fields do
    values = Enum.map(values, &String.downcase/1)

    projects_query(opts)
    |> where([p], fragment("LOWER(?)", field(p, ^field)) in ^values)
    |> Repo.all()
  end

  def by_field(values, field, opts) when is_list(values) do
    projects_query(opts)
    |> where([p], field(p, ^field) in ^values)
    |> Repo.all()
  end

  def by_contracts(contracts, opts \\ [])

  def by_contracts(contracts, opts) when is_list(contracts) do
    contracts = Enum.map(contracts, &String.downcase/1)

    from(
      p in projects_query(opts),
      inner_join: contract in assoc(p, :contract_addresses),
      where: contract.address in ^contracts
    )
    |> Repo.all()
  end

  @doc ~s"""
  Returns a list of projects that have their ticker, name and/or slug in the list of
  values. This function is used when deciding what is the list of trending
  projects, as a project is defined as trending when its slug, ticker and/or slug
  is in the list of trending words.
  Filtering out projects based on some conditions can be controled by the options.

  See the "Shared options" section at the module documentation for more options.
  """
  def by_name_ticker_slug(values, opts \\ [])

  def by_name_ticker_slug(values, opts) do
    values = List.wrap(values)

    from(
      p in projects_query(opts),
      where:
        fragment("lower(?)", p.name) in ^values or
          fragment("lower(?)", p.ticker) in ^values or
          fragment("lower(?)", p.slug) in ^values
    )
    |> Repo.all()
  end

  @doc ~s"""
  Returns the list of currently trending project. A project is trending if
  one or all of its name, ticker and slug are present int he trending words.
  Filtering out projects based on some conditions can be controled by the options.

  See the "Shared options" section at the module documentation for more options.
  """
  def currently_trending_projects(opts \\ [])

  def currently_trending_projects(opts) do
    {:ok, trending_words} = Sanbase.SocialData.TrendingWords.get_currently_trending_words(10)

    trending_words
    |> Enum.map(&String.downcase(&1.word))
    |> by_name_ticker_slug(opts)
  end

  # Private functions

  ## Fetch list of projects
  defp projects_query(opts) do
    from(
      p in Project,
      where: not is_nil(p.slug) and not is_nil(p.ticker)
    )
    |> maybe_preload(opts)
    |> maybe_only_included_slugs(opts)
    |> maybe_order_by_slugs_list(opts)
    |> maybe_paginate(opts)
    |> maybe_include_hidden_projects(opts)
    |> maybe_order_by_rank_optional(opts)
    |> maybe_order_by_rank_above_volume(opts)
  end

  defp erc20_projects_query(opts) do
    # If the opts have included_slugs: :erc20 then the filter_erc20_projects/1
    # function will be called twice - once here and once from the projects_query(opts)
    # Fix this by removing :included_slugs only in this case. Do not change them in
    # other cases as this option can be used to further filter the projects.
    opts =
      if Keyword.get(opts, :included_slugs) == :erc20,
        do: Keyword.delete(opts, :included_slugs),
        else: opts

    projects_query(opts)
    |> filter_erc20_projects()
  end

  defp filter_erc20_projects(query) do
    from(
      p in query,
      inner_join: infr in assoc(p, :infrastructure),
      inner_join: contract in assoc(p, :contract_addresses),
      where: not is_nil(contract.id) and infr.code == "ETH"
    )
  end

  defp currency_projects_query(opts) do
    from(
      p in projects_query(opts),
      left_join: infr in assoc(p, :infrastructure),
      left_join: contract in assoc(p, :contract_addresses),
      where: is_nil(contract.id) or is_nil(p.infrastructure_id) or infr.code != "ETH"
    )
  end

  ## Pagination queries

  defp projects_page_query(page, page_size, opts) do
    projects_query(opts)
    |> order_by_rank(opts)
    |> page(page, page_size)
  end

  defp erc20_projects_page_query(page, page_size, opts) do
    erc20_projects_query(opts)
    |> order_by_rank(opts)
    |> page(page, page_size)
  end

  defp currency_projects_page_query(page, page_size, opts) do
    currency_projects_query(opts)
    |> order_by_rank(opts)
    |> page(page, page_size)
  end

  defp page(query, page, page_size) do
    query
    |> offset(^((page - 1) * page_size))
    |> limit(^page_size)
  end

  # Add an optional ordering by rank. If the project has no known rank, the project
  # is not excluded but is put at the end of the list. The order of projects
  # with no known rank is not defined
  defp maybe_order_by_rank_optional(query, opts) do
    case Keyword.get(opts, :order_by_rank, false) do
      true ->
        from(
          p in query,
          left_join: latest_cmc in assoc(p, :latest_coinmarketcap_data),
          order_by: latest_cmc.rank
        )

      false ->
        query
    end
  end

  defp order_by_rank(query, opts) do
    case Keyword.get(opts, :min_volume) do
      nil ->
        from(p in query,
          inner_join: latest_cmc in assoc(p, :latest_coinmarketcap_data),
          order_by: latest_cmc.rank
        )

      _ ->
        # If there is min_volume that is not nil, then the
        # `maybe_order_by_rank_above_volume` function has been executed which
        # has done the ordering by rank. This extra check is done to avoid
        # double joining of the tables.
        #
        # NOTE: This can be improved when Ecto is updated to 3.x where named
        # bindings can be used
        query
    end
  end

  defp maybe_order_by_rank_above_volume(query, opts) do
    case Keyword.get(opts, :min_volume, nil) do
      nil ->
        query

      min_volume ->
        from(
          p in query,
          inner_join: latest_cmc in assoc(p, :latest_coinmarketcap_data),
          where: latest_cmc.volume_usd >= ^min_volume,
          order_by: latest_cmc.rank
        )
    end
  end

  defp maybe_include_hidden_projects(query, opts) do
    case Keyword.get(opts, :include_hidden, false) do
      false ->
        query
        |> where([p], p.is_hidden == false)

      true ->
        query
    end
  end

  defp maybe_preload(query, opts) do
    case Keyword.get(opts, :preload?, true) do
      true ->
        preloads = Keyword.get(opts, :preload, @preloads)
        query |> preload(^preloads)

      false ->
        query
    end
  end

  defp maybe_only_included_slugs(query, opts) do
    case Keyword.get(opts, :included_slugs, :all) do
      # Do not exclude any projects
      :all ->
        query

      :erc20 ->
        query
        |> filter_erc20_projects()

      slugs when is_list(slugs) ->
        query
        |> where([p], p.slug in ^slugs)
    end
  end

  defp maybe_order_by_slugs_list(query, opts) do
    case Keyword.get(opts, :ordered_slugs) do
      # Do not exclude any projects
      slugs when is_list(slugs) ->
        query
        |> order_by([p], fragment("array_position(?, ?)", ^slugs, p.slug))

      _ ->
        case Keyword.get(opts, :order_by_name?, false) do
          true ->
            query
            |> order_by([p], p.name)

          false ->
            query
        end
    end
  end

  defp maybe_paginate(query, opts) do
    case Keyword.get(opts, :has_pagination?) do
      # Do not exclude any projects
      true ->
        page = opts[:pagination][:page]
        page_size = opts[:pagination][:page_size]

        query
        |> page(page, page_size)

      _ ->
        query
    end
  end
end
