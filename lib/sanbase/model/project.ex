defmodule Sanbase.Model.Project do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Repo
  alias Sanbase.Prices.Store

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
      |> Enum.reduce({project, 0, zero}, &roi_usd_total_paid_accumulator/2)
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

  defp roi_usd_total_paid_accumulator(ico, {project, count, total_paid}) do
    (ico.token_usd_ico_price
        || token_usd_ico_price(ico.token_eth_ico_price, "ETH", ico.start_date, project.latest_coinmarketcap_data.update_time)
        || token_usd_ico_price(ico.token_btc_ico_price, "BTC", ico.start_date, project.latest_coinmarketcap_data.update_time))
    |> case do
      nil -> {project, count, total_paid}
      0 -> {project, count, total_paid}
      price_usd -> {project, count+1, Decimal.add(total_paid, Decimal.new(price_usd))}
    end
  end

  defp token_usd_ico_price(nil, _currency_from, _ico_start_date, _current_datetime), do: nil
  defp token_usd_ico_price(_price_from, _currency_from, nil, _current_datetime), do: nil
  defp token_usd_ico_price(price_from, currency_from, ico_start_date, current_datetime) do
    with :gt <- Ecto.DateTime.compare(current_datetime, Ecto.DateTime.from_date(ico_start_date)),
        {:ok, timestamp, _} <- Ecto.Date.to_iso8601(ico_start_date) <> "T00:00:00Z" |> DateTime.from_iso8601(),
        {_, price, _, _} <- Store.fetch_last_known_price_point(currency_from <> "_USD", timestamp) do
      Decimal.mult(price_from, Decimal.new(price))
    else
      _ -> nil
    end
  end
end
