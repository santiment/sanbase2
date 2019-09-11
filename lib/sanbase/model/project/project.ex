defmodule Sanbase.Model.Project do
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__
  alias Sanbase.Repo

  alias Sanbase.Model.{
    ProjectEthAddress,
    ProjectBtcAddress,
    Ico,
    Currency,
    MarketSegment,
    Infrastructure,
    LatestCoinmarketcapData,
    ProjectTransparencyStatus
  }

  import Ecto.Query

  @preloads [:eth_addresses, :latest_coinmarketcap_data, :github_organizations]

  schema "project" do
    field(:name, :string)
    field(:ticker, :string)
    field(:logo_url, :string)
    field(:website_link, :string)
    field(:email, :string)
    field(:btt_link, :string)
    field(:facebook_link, :string)
    field(:github_link, :string)
    field(:reddit_link, :string)
    field(:twitter_link, :string)
    field(:whitepaper_link, :string)
    field(:blog_link, :string)
    field(:slack_link, :string)
    field(:linkedin_link, :string)
    field(:telegram_link, :string)
    field(:token_address, :string)
    field(:team_token_wallet, :string)
    field(:token_decimals, :integer)
    field(:total_supply, :decimal)
    field(:description, :string)
    field(:long_description, :string)
    field(:project_transparency, :boolean, default: false)
    field(:main_contract_address, :string)
    field(:project_transparency_description, :string)

    has_one(:social_volume_query, Project.SocialVolumeQuery)

    has_many(:source_slug_mappings, Project.SourceSlugMapping)
    has_many(:icos, Ico)
    has_many(:github_organizations, Project.GithubOrganization)
    has_many(:eth_addresses, ProjectEthAddress)
    has_many(:btc_addresses, ProjectBtcAddress)

    belongs_to(:market_segment, MarketSegment, on_replace: :nilify)
    belongs_to(:infrastructure, Infrastructure, on_replace: :nilify)
    belongs_to(:project_transparency_status, ProjectTransparencyStatus, on_replace: :nilify)

    belongs_to(
      :latest_coinmarketcap_data,
      LatestCoinmarketcapData,
      foreign_key: :slug,
      references: :coinmarketcap_id,
      type: :string,
      on_replace: :nilify
    )

    many_to_many(
      :market_segments,
      MarketSegment,
      join_through: "project_market_segments",
      on_replace: :delete,
      on_delete: :delete_all
    )
  end

  def changeset(%Project{} = project, attrs \\ %{}) do
    project
    |> cast(attrs, [
      :name,
      :ticker,
      :logo_url,
      :slug,
      :website_link,
      :email,
      :market_segment_id,
      :infrastructure_id,
      :btt_link,
      :facebook_link,
      :github_link,
      :reddit_link,
      :twitter_link,
      :whitepaper_link,
      :blog_link,
      :slack_link,
      :linkedin_link,
      :telegram_link,
      :token_address,
      :main_contract_address,
      :team_token_wallet,
      :description,
      :long_description,
      :project_transparency,
      :project_transparency_status_id,
      :project_transparency_description,
      :token_decimals,
      :total_supply
    ])
    |> cast_assoc(:market_segments)
    |> validate_required([:name])
    |> unique_constraint(:slug)
  end

  defdelegate roi_usd(project), to: Project.Roi

  defdelegate ico_price(project), to: Project.FundsRaised

  defdelegate initial_ico(project), to: Project.FundsRaised

  defdelegate funds_raised_usd_ico_end_price(project), to: Project.FundsRaised

  defdelegate funds_raised_eth_ico_end_price(project), to: Project.FundsRaised

  defdelegate funds_raised_btc_ico_end_price(project), to: Project.FundsRaised

  defdelegate funds_raised_icos(project), to: Project.FundsRaised

  defdelegate describe(project), to: Project.Description

  defdelegate contract_info_by_slug(slug), to: Project.ContractData

  defdelegate contract_info(project), to: Project.ContractData

  defdelegate contract_address(project), to: Project.ContractData

  def coinmarketcap_id(%Project{} = project) do
    Project.SourceSlugMapping.get_slug(project, "coinmarketcap")
  end

  def sanbase_link(%Project{slug: slug}) when not is_nil(slug) do
    SanbaseWeb.Endpoint.frontend_url() <> "/projects/#{slug}"
  end

  def supply(%Project{} = project) do
    case get_supply(project) do
      nil -> nil
      s -> Decimal.to_float(s)
    end
  end

  defp get_supply(%Project{total_supply: ts, latest_coinmarketcap_data: nil}), do: ts

  defp get_supply(%Project{total_supply: ts, latest_coinmarketcap_data: lcd}) do
    lcd.available_supply || lcd.total_supply || ts
  end

  @doc ~s"""
  Return a project with a matching ticker. `Repo.one` fails if there are more
  than one project with the same ticker.
  """
  @spec by_currency(%Currency{}) :: %Project{} | no_return()
  def by_currency(%Currency{code: code}) do
    from(
      p in Project,
      where: p.ticker == ^code and not is_nil(p.slug)
    )
    |> Repo.one()
  end

  def id_by_slug(slug) do
    from(p in __MODULE__, where: p.slug == ^slug, select: p.id) |> Repo.one()
  end

  def by_slug(slug, opts \\ [])

  def by_slug(slug, opts) when is_binary(slug) do
    Project
    |> where([p], p.slug == ^slug)
    |> preload_query(opts)
    |> Repo.one()
  end

  def by_slug(slugs, opts) when is_list(slugs) do
    Project
    |> where([p], p.slug in ^slugs)
    |> preload_query(opts)
    |> Repo.all()
  end

  def by_id(id, opts \\ []) when is_integer(id) or is_binary(id) do
    Project
    |> where([p], p.id == ^id)
    |> preload_query(opts)
    |> Repo.one()
  end

  def ticker_by_slug(nil), do: nil
  def ticker_by_slug("TOTAL_MARKET"), do: "TOTAL_MARKET"

  def ticker_by_slug(slug) when is_binary(slug) do
    from(
      p in Sanbase.Model.Project,
      where: p.slug == ^slug and not is_nil(p.ticker),
      select: p.ticker
    )
    |> Sanbase.Repo.one()
  end

  def slug_by_ticker(nil), do: nil
  def slug_by_ticker("TOTAL_MARKET"), do: "TOTAL_MARKET"

  def slug_by_ticker(ticker) do
    from(
      p in Project,
      where: p.ticker == ^ticker and not is_nil(p.slug),
      select: p.slug
    )
    |> Repo.all()
    |> List.first()
  end

  def tickers_by_slug_list(slugs_list) when is_list(slugs_list) do
    from(
      p in Sanbase.Model.Project,
      where: p.slug in ^slugs_list and not is_nil(p.ticker),
      select: {p.ticker, p.slug}
    )
    |> Sanbase.Repo.all()
  end

  def eth_addresses(%Project{} = project) do
    project =
      project
      |> Repo.preload([:eth_addresses])

    addresses =
      project.eth_addresses
      |> Enum.map(fn %{address: address} -> address end)

    {:ok, addresses}
  end

  def eth_addresses(projects) when is_list(projects) do
    ids = for %Project{id: id} <- projects, do: id

    addresses =
      from(
        p in Project,
        where: p.id in ^ids,
        preload: [:eth_addresses]
      )
      |> Repo.all()
      |> Enum.map(fn %Project{eth_addresses: project_eth_addresses} ->
        project_eth_addresses
        |> Enum.map(fn %ProjectEthAddress{address: address} -> address end)
      end)
      |> Enum.reject(fn x -> x == [] end)

    {:ok, addresses}
  end

  @doc """
  Return all projects from the list which trading volume is over a given threshold
  """
  def projects_over_volume_threshold(projects, volume_threshold) do
    measurements_list =
      projects
      |> Enum.map(fn %Project{} = project -> Sanbase.Influxdb.Measurement.name_from(project) end)
      |> Enum.reject(&is_nil/1)

    case measurements_list do
      [] ->
        []

      [_ | _] ->
        measurements_str =
          measurements_list
          |> Enum.map(fn x -> "\"#{x}\"" end)
          |> Enum.join(", ")

        volume_over_threshold_projects =
          Sanbase.Prices.Store.volume_over_threshold(
            measurements_str,
            Timex.shift(Timex.now(), days: -1),
            Timex.now(),
            volume_threshold
          )

        projects
        |> Enum.filter(fn %Project{} = project ->
          Sanbase.Influxdb.Measurement.name_from(project) in volume_over_threshold_projects
        end)
    end
  end

  def github_organizations(slug) when is_binary(slug) do
    case id_by_slug(slug) do
      nil ->
        {:error,
         "Cannot fetch github organizations for #{slug}. Reason: There is no project with that slug."}

      id ->
        {:ok, Project.GithubOrganization.organizations_of(id)}
    end
  end

  def github_organizations(%Project{} = project) do
    {:ok, project |> Project.GithubOrganization.organizations_of()}
  end

  def is_erc20?(%Project{} = project) do
    project
    |> Repo.preload(:infrastructure)
    |> case do
      %Project{main_contract_address: contract, infrastructure: %Infrastructure{code: "ETH"}}
      when not is_nil(contract) ->
        true

      _ ->
        false
    end
  end

  def is_currency?(%Project{} = project) do
    not is_erc20?(project)
  end

  def preloads(), do: @preloads

  def preload_assocs(projects, opts \\ []) do
    additional_preloads = Keyword.get(opts, :additional_preloads, [])
    Repo.preload(projects, additional_preloads ++ @preloads)
  end

  defp preload_query(query, opts) do
    additional_preloads = Keyword.get(opts, :additional_preloads, [])

    query
    |> preload(^(additional_preloads ++ @preloads))
  end
end
