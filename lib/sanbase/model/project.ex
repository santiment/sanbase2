defmodule Sanbase.Model.Project do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.{Project, ProjectEthAddress, ProjectBtcAddress, Ico, MarketSegment, Infrastructure}


  schema "project" do
    field :name, :string
    field :ticker, :string
    field :logo_url, :string
    field :coinmarketcap_id, :string
    field :website_link, :string
    field :btt_link, :string
    field :facebook_link, :string
    field :github_link, :string
    field :reddit_link, :string
    field :twitter_link, :string
    field :whitepaper_link, :string
    has_many :eth_addresses, ProjectEthAddress
    has_many :btc_addresses, ProjectBtcAddress
    belongs_to :market_segment, MarketSegment
    belongs_to :infrastructure, Infrastructure
  end

  @doc false
  def changeset(%Project{} = project, attrs \\ %{}) do
    project
    |> cast(attrs, [:name, :ticker, :logo_url, :coinmarketcap_id, :website_link, :market_segment_id, :infrastructure_id, :btt_link, :facebook_link, :github_link, :reddit_link, :twitter_link, :whitepaper_link])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
