defmodule Sanbase.Model.Project do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.{Project, ProjectEthAddress, ProjectBtcAddress, Ico, MarketSegment, Infrastructure, LatestCoinmarketcapData}


  schema "project" do
    field :name, :string
    field :ticker, :string
    field :logo_url, :string
    field :website_link, :string
    field :btt_link, :string
    field :facebook_link, :string
    field :github_link, :string
    field :reddit_link, :string
    field :twitter_link, :string
    field :whitepaper_link, :string
    field :blog_link, :string
    field :slack_link, :string
    field :linkedin_link, :string
    field :telegram_link, :string
    field :project_transparency, :string
    field :token_address, :string
    field :team_token_wallet, :string
    has_many :eth_addresses, ProjectEthAddress
    has_many :btc_addresses, ProjectBtcAddress
    belongs_to :market_segment, MarketSegment, on_replace: :nilify
    belongs_to :infrastructure, Infrastructure, on_replace: :nilify
    belongs_to :latest_coinmarketcap_data, LatestCoinmarketcapData, foreign_key: :coinmarketcap_id, references: :coinmarketcap_id, type: :string, on_replace: :nilify
    has_one :ico, Ico
  end

  @doc false
  def changeset(%Project{} = project, attrs \\ %{}) do
    project
    |> cast(attrs, [:name, :ticker, :logo_url, :coinmarketcap_id, :website_link, :market_segment_id, :infrastructure_id, :btt_link, :facebook_link, :github_link, :reddit_link, :twitter_link, :whitepaper_link, :blog_link, :slack_link, :linkedin_link, :telegram_link, :project_transparency, :team_token_wallet])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
