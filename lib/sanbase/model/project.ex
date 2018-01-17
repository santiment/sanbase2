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
    field(:token_decimals, :integer)
    field(:total_supply, :decimal)
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
         :project_transparency_description,
         :token_decimals,
         :total_supply
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
      amounts -> Enum.reduce(amounts, Decimal.new(0), &Decimal.add/2)
    end
  end

  @doc """
  For every currency aggregates all amounts for every ICO of the given project
  """
  def funds_raised_icos(%Project{id: id}) do
    query = from i in Ico,
            inner_join: ic in IcoCurrencies, on: ic.ico_id == i.id and not is_nil(ic.amount),
            inner_join: c in Currency, on: c.id == ic.currency_id,
            where: i.project_id == ^id,
            group_by: c.code,
            order_by: fragment("case
                            			when ? = 'BTC' then '_'
                            			when ? = 'ETH' then '__'
                            			when ? = 'USD' then '___'
                            		  else ?
                            		end", c.code, c.code, c.code, c.code),
            select: %{currency_code: c.code, amount: sum(ic.amount)}

    Repo.all(query)
  end
end
