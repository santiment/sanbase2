defmodule Sanbase.Model.Project do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.{Project, ProjectEthAddress, ProjectBtcAddress, Btt, Facebook, Github, Ico, Reddit, Team, Twitter, Whitepaper, MarketSegment, Infrastructure, Country, Prices}


  schema "project" do
    field :name, :string
    field :ticker, :string
    field :logo_url, :string
    field :coinmarketcap_id, :string
    field :geolocation_city, :string
    field :website_link, :string
    field :open_source, :boolean
    has_many :eth_addresses, ProjectEthAddress
    has_many :btc_addresses, ProjectBtcAddress
    belongs_to :market_segment, MarketSegment
    belongs_to :infrastructure, Infrastructure
    belongs_to :geolocation_country, Country
    has_one :btt, Btt
    has_one :facebook, Facebook
    has_one :github, Github
    has_one :ico, Ico
    has_one :reddit, Reddit
    has_one :team, Team
    has_one :twitter, Twitter
    has_one :whitepaper, Whitepaper
    has_one :prices, Prices
  end

  @doc false
  def changeset(%Project{} = project, attrs \\ %{}) do
    project
    |> cast(attrs, [:name, :ticker, :logo_url, :coinmarketcap_id, :geolocation_city, :website_link, :open_source, :market_segment_id, :infrastructure_id, :geolocation_country_id])
    |> validate_required([:name, :ticker])
    |> unique_constraint(:name)
  end
end
