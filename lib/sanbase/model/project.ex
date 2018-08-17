defmodule Sanbase.Model.Project do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Repo

  alias Sanbase.Model.{
    Project,
    ProjectEthAddress,
    ProjectBtcAddress,
    Ico,
    IcoCurrencies,
    Currency,
    MarketSegment,
    Infrastructure,
    LatestCoinmarketcapData,
    ProjectTransparencyStatus
  }

  import Ecto.Query

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
    field(:project_transparency, :boolean, default: false)
    field(:main_contract_address, :string)
    belongs_to(:project_transparency_status, ProjectTransparencyStatus, on_replace: :nilify)
    field(:project_transparency_description, :string)
    has_many(:eth_addresses, ProjectEthAddress)
    has_many(:btc_addresses, ProjectBtcAddress)
    belongs_to(:market_segment, MarketSegment, on_replace: :nilify)
    belongs_to(:infrastructure, Infrastructure, on_replace: :nilify)

    belongs_to(
      :latest_coinmarketcap_data,
      LatestCoinmarketcapData,
      foreign_key: :coinmarketcap_id,
      references: :coinmarketcap_id,
      type: :string,
      on_replace: :nilify
    )

    has_many(:icos, Ico)
  end

  @doc false
  def changeset(%Project{} = project, attrs \\ %{}) do
    project
    |> cast(attrs, [
      :name,
      :ticker,
      :logo_url,
      :coinmarketcap_id,
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
      :project_transparency,
      :project_transparency_status_id,
      :project_transparency_description,
      :token_decimals,
      :total_supply
    ])
    |> validate_required([:name])
    |> unique_constraint(:coinmarketcap_id)
  end

  def initial_ico(%Project{id: id}) do
    Ico
    |> where([i], i.project_id == ^id)
    |> first(:start_date)
    |> Repo.one()
  end

  @doc ~S"""
  ROI = current_price*(ico1_tokens + ico2_tokens + ...)/(ico1_tokens*ico1_initial_price + ico2_tokens*ico2_initial_price + ...)
  We skip ICOs for which we can't calculate the initial_price or the tokens sold
  For ICOs that we don't have tokens sold we try to fill it heuristically by evenly distributing the rest of the total available supply
  """
  def roi_usd(%Project{ticker: ticker, coinmarketcap_id: coinmarketcap_id} = project)
      when not is_nil(ticker) and not is_nil(coinmarketcap_id) do
    with %Project{} = project <- Repo.preload(project, [:latest_coinmarketcap_data, :icos]),
         false <- is_nil(project.latest_coinmarketcap_data),
         false <- is_nil(project.latest_coinmarketcap_data.price_usd),
         false <- is_nil(project.latest_coinmarketcap_data.available_supply) do
      zero = Decimal.new(0)

      tokens_and_initial_prices =
        project
        |> fill_missing_tokens_sold_at_icos()
        |> Enum.map(fn ico ->
          {ico.tokens_sold_at_ico, calc_token_usd_ico_price_by_project(project, ico)}
        end)
        |> Enum.reject(fn {tokens_sold_at_ico, token_usd_ico_price} ->
          is_nil(tokens_sold_at_ico) or is_nil(token_usd_ico_price)
        end)

      total_cost =
        tokens_and_initial_prices
        |> Enum.map(fn {tokens_sold_at_ico, token_usd_ico_price} ->
          Decimal.mult(tokens_sold_at_ico, token_usd_ico_price)
        end)
        |> Enum.reduce(zero, &Decimal.add/2)

      total_gain =
        tokens_and_initial_prices
        |> Enum.map(fn {tokens_sold_at_ico, _} -> tokens_sold_at_ico end)
        |> Enum.reduce(zero, &Decimal.add/2)
        |> Decimal.mult(project.latest_coinmarketcap_data.price_usd)

      case total_cost do
        ^zero -> nil
        total_cost -> Decimal.div(total_gain, total_cost)
      end
    else
      _ -> nil
    end
  end

  def roi_usd(_), do: nil

  @doc ~S"""
    Returns an Ecto query that selects all projects with eth contract
  """
  @spec all_projects_with_eth_contract_query() :: %Ecto.Query{}
  def all_projects_with_eth_contract_query() do
    all_icos_query =
      from(
        i in Ico,
        select: %{
          project_id: i.project_id,
          contract_block_number: i.contract_block_number,
          contract_abi: i.contract_abi,
          rank:
            fragment(
              "row_number() over(partition by ? order by ? asc)",
              i.project_id,
              i.start_date
            )
        }
      )

    query =
      from(
        d in subquery(all_icos_query),
        inner_join: p in Project,
        on: p.id == d.project_id,
        where:
          not is_nil(p.coinmarketcap_id) and d.rank == 1 and not is_nil(p.main_contract_address) and
            not is_nil(d.contract_block_number) and not is_nil(d.contract_abi),
        order_by: p.name,
        select: p
      )

    query
  end

  # Private functions

  # Heuristic: fills empty ico.tokens_sold_at_ico by evenly distributing the rest of the circulating supply
  # TODO:
  # Currently uses latest_coinmarketcap_data.available_supply, which also includes coins not issued at any ICO
  # Maybe it's better to keep historical data of available_supply so that we can calculate it better
  defp fill_missing_tokens_sold_at_icos(%Project{} = project) do
    with tokens_sold_at_icos <- Enum.map(project.icos, & &1.tokens_sold_at_ico),
         unknown_count <- Enum.filter(tokens_sold_at_icos, &is_nil/1) |> length(),
         true <- unknown_count > 0 do
      zero = Decimal.new(0)
      one = Decimal.new(1)

      known_tokens_sum =
        tokens_sold_at_icos
        |> Enum.reject(&is_nil/1)
        |> Enum.reduce(zero, &Decimal.add/2)

      unknown_tokens_sum =
        Decimal.compare(project.latest_coinmarketcap_data.available_supply, known_tokens_sum)
        |> case do
          ^one ->
            Decimal.sub(project.latest_coinmarketcap_data.available_supply, known_tokens_sum)

          _ ->
            zero
        end

      unknown_tokens_single_ico = Decimal.div(unknown_tokens_sum, Decimal.new(unknown_count))

      Enum.map(project.icos, fn ico ->
        if is_nil(ico.tokens_sold_at_ico) do
          Map.put(ico, :tokens_sold_at_ico, unknown_tokens_single_ico)
        else
          ico
        end
      end)
    else
      _ -> project.icos
    end
  end

  defp calc_token_usd_ico_price_by_project(%Project{} = project, %Ico{} = ico) do
    ico.token_usd_ico_price ||
      calc_token_usd_ico_price(
        ico.token_eth_ico_price,
        "ETH",
        ico.start_date,
        project.latest_coinmarketcap_data.update_time
      ) ||
      calc_token_usd_ico_price(
        ico.token_btc_ico_price,
        "BTC",
        ico.start_date,
        project.latest_coinmarketcap_data.update_time
      )
  end

  defp calc_token_usd_ico_price(nil, _currency_from, _ico_start_date, _current_datetime), do: nil
  defp calc_token_usd_ico_price(_price_from, _currency_from, nil, _current_datetime), do: nil

  defp calc_token_usd_ico_price(price_from, currency_from, ico_start_date, current_datetime) do
    with :gt <- Ecto.DateTime.compare(current_datetime, Ecto.DateTime.from_date(ico_start_date)),
         timestamp <- Sanbase.DateTimeUtils.ecto_date_to_datetime(ico_start_date),
         price_usd when not is_nil(price_usd) <-
           Sanbase.Prices.Utils.fetch_last_price_before(currency_from, "USD", timestamp) do
      Decimal.mult(price_from, Decimal.new(price_usd))
    else
      _ -> nil
    end
  end

  def funds_raised_usd_ico_end_price(project) do
    funds_raised_ico_end_price(project, &Ico.funds_raised_usd_ico_end_price/1)
  end

  def funds_raised_eth_ico_end_price(project) do
    funds_raised_ico_end_price(project, &Ico.funds_raised_eth_ico_end_price/1)
  end

  def funds_raised_btc_ico_end_price(project) do
    funds_raised_ico_end_price(project, &Ico.funds_raised_btc_ico_end_price/1)
  end

  defp funds_raised_ico_end_price(project, ico_funds_raised_fun) do
    Repo.preload(project, :icos).icos
    |> Enum.map(ico_funds_raised_fun)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      amounts -> Enum.reduce(amounts, 0, &Kernel.+/2)
    end
  end

  @doc """
  For every currency aggregates all amounts for every ICO of the given project
  """
  def funds_raised_icos(%Project{id: id}) do
    query =
      from(
        i in Ico,
        inner_join: ic in IcoCurrencies,
        on: ic.ico_id == i.id and not is_nil(ic.amount),
        inner_join: c in Currency,
        on: c.id == ic.currency_id,
        where: i.project_id == ^id,
        group_by: c.code,
        order_by: fragment("case
                            			when ? = 'BTC' then '_'
                            			when ? = 'ETH' then '__'
                            			when ? = 'USD' then '___'
                            		  else ?
                            		end", c.code, c.code, c.code, c.code),
        select: %{currency_code: c.code, amount: sum(ic.amount)}
      )

    Repo.all(query)
  end

  def eth_addresses_by_tickers(tickers) do
    query =
      from(
        p in Project,
        where: p.ticker in ^tickers and not is_nil(p.coinmarketcap_id),
        preload: [:eth_addresses]
      )

    Repo.all(query)
    |> Stream.map(fn %Project{ticker: ticker, eth_addresses: eth_addresses} ->
      eth_addresses = eth_addresses |> Enum.map(&Map.get(&1, :address))

      {ticker, eth_addresses}
    end)
    |> Enum.into(%{})
  end

  def ticker_by_slug(nil), do: nil

  def ticker_by_slug(slug) when is_binary(slug) do
    from(
      p in Sanbase.Model.Project,
      where: p.coinmarketcap_id == ^slug and not is_nil(p.ticker),
      select: p.ticker
    )
    |> Sanbase.Repo.one()
  end
end
