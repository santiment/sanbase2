defmodule Sanbase.Model.Project do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Repo

  alias Sanbase.Model.{
    Project,
    ProjectEthAddress,
    ProjectBtcAddress,
    Ico,
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
    field(:project_transparency, :boolean, default: false)
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
         :team_token_wallet,
         :project_transparency,
         :project_transparency_status_id,
         :project_transparency_description
       ])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end

  def initial_ico(%Project{id: id}) do
    Ico
    |> where([i], i.project_id == ^id)
    |> first(:start_date)
    |> Repo.one
  end

  def roi_usd(%Project{ticker: ticker, coinmarketcap_id: coinmarketcap_id} = project) when not is_nil(ticker) and not is_nil(coinmarketcap_id) do
    with project <- Repo.preload(project, [:icos, :latest_coinmarketcap_data]),
        true <- !is_nil(project.latest_coinmarketcap_data)
              and !is_nil(project.latest_coinmarketcap_data.price_usd) do

      zero = Decimal.new(0)

      project.icos
      |> Enum.reduce({project, 0, zero}, &roi_usd_accumulator/2)
      |> case do
        {_, _, ^zero} -> nil
        {_, count, total_paid} ->
          project.latest_coinmarketcap_data.price_usd
          |> Decimal.mult(Decimal.new(count))
          |> Decimal.div(total_paid)
      end
    else
      _ -> nil
    end
  end
  def roi_usd(_), do: nil

  defp roi_usd_accumulator(%Ico{end_date: nil}, {project, count, total_paid}), do: {project, count, total_paid}
  defp roi_usd_accumulator(%Ico{end_date: end_date}, {project, count, total_paid}) do
    with :gt <- Ecto.DateTime.compare(project.latest_coinmarketcap_data.update_time, Ecto.DateTime.from_date(end_date)),
        timestamp <- Sanbase.DateTimeUtils.ecto_date_to_datetime(end_date) do

      Sanbase.Prices.Utils.fetch_last_price_before(project.ticker, "USD", timestamp)
      |> case do
        nil -> {project, count, total_paid}
        0 -> {project, count, total_paid}
        price_at_ico_end -> {project, count+1, Decimal.add(total_paid, Decimal.new(price_at_ico_end))}
      end
    else
      _ -> {project, count, total_paid}
    end
  end

  def funds_raised_usd_ico_price(project) do
    Repo.preload(project, :icos).icos
    |> Enum.reduce(nil, fn(ico, acc) ->
      add_if_not_nil(acc, Ico.funds_raised_usd_ico_price(ico))
    end)
  end

  def funds_raised_eth_ico_price(project) do
    Repo.preload(project, :icos).icos
    |> Enum.reduce(nil, fn(ico, acc) ->
      add_if_not_nil(acc, Ico.funds_raised_eth_ico_price(ico))
    end)
  end

  def funds_raised_btc_ico_price(project) do
    Repo.preload(project, :icos).icos
    |> Enum.reduce(nil, fn(ico, acc) ->
      add_if_not_nil(acc, Ico.funds_raised_btc_ico_price(ico))
    end)
  end

  def funds_raised_all_ico_price(project) do
    Repo.preload(project, :icos).icos
    |> Enum.reduce(%{funds_raised_usd: nil, funds_raised_eth: nil, funds_raised_btc: nil},
    fn(ico, %{funds_raised_usd: acc_usd, funds_raised_eth: acc_eth, funds_raised_btc: acc_btc}) ->
      %{funds_raised_usd: ico_usd, funds_raised_eth: ico_eth, funds_raised_btc: ico_btc} = Ico.funds_raised_all_ico_price(ico)

      %{funds_raised_usd: add_if_not_nil(acc_usd, ico_usd),
        funds_raised_eth: add_if_not_nil(acc_eth, ico_eth),
        funds_raised_btc: add_if_not_nil(acc_btc, ico_btc)}
    end)
  end

  # If there is no raw data for any currency for a given ico, then fallback one of the precalculated totals - one of Ico.funds_raised_usd, Ico.funds_raised_eth, Ico.funds_raised_btc (checked in that order)
  def funds_raised_icos(%Project{id: id}) do
    # We have to aggregate all amounts for every currency for every ICO of the given project, this is the last part of the query (after the with clause).
    # The data to be aggreagated has to be fetched and unioned from two different sources (the "union all" inside the with clause):
    #   * For ICOs that have raw data entered for at least one currency we aggregate it by currency (the first query)
    #   * For ICOs that don't have that data entered (currently everything imported from the spreadsheet) we fall back to a precalculated total (the second query)
    query =
      '''
      with data as (select c.code currency_code, ic.amount
      from icos i
      join ico_currencies ic
      	on ic.ico_id = i.id
      		and ic.amount is not null
      join currencies c
      	on c.id = ic.currency_id
      where i.project_id = $1
      union all
      select case
      		when i.funds_raised_usd is not null then 'USD'
      		when i.funds_raised_eth is not null then 'ETH'
          when i.funds_raised_btc is not null then 'BTC'
      		else null
      	end currency_code
      	, coalesce(i.funds_raised_usd, i.funds_raised_btc, i.funds_raised_eth) amount
      from icos i
      where i.project_id = $1
      	and not exists (select 1
      		from ico_currencies ic
      		where ic.ico_id = i.id
      			and ic.amount is not null))
      select d.currency_code, sum(d.amount) amount
      from data d
      where d.currency_code is not null
      group by d.currency_code
      order by case
          			when d.currency_code = 'BTC' then '_'
          			when d.currency_code = 'ETH' then '__'
          			when d.currency_code = 'USD' then '___'
          			else d.currency_code
          		end
      '''

      %{rows: rows} = Ecto.Adapters.SQL.query!(Sanbase.Repo, query, [id])

      rows |> Enum.map(fn([currency_code, amount]) -> %{currency_code: currency_code, amount: amount} end)
  end

  defp add_if_not_nil(first, second) do
    cond do
      !is_nil(first) and !is_nil(second) -> Decimal.add(first, second)
      !is_nil(first) -> first
      !is_nil(second) -> second
      true -> nil
    end
  end
end
