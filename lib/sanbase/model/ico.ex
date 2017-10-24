defmodule Sanbase.Model.Ico do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.Ico
  alias Sanbase.Model.Project
  alias Sanbase.Model.Currency


  schema "icos" do
    field :bounty_campaign, :boolean, default: false
    field :end_date, Ecto.Date
    field :funds_raised_btc, :decimal
    field :highest_bonus_percent_for_ico, :decimal
    field :ico_contributors, :integer
    field :maximal_cap_amount, :decimal
    field :maximal_cap_archived, :boolean, default: false
    field :minimal_cap_amount, :decimal
    field :minimal_cap_archived, :boolean, default: false
    field :percent_tokens_for_bounties, :decimal
    field :start_date, Ecto.Date
    field :tokens_issued_at_ico, :integer
    field :tokens_sold_at_ico, :integer
    field :tokens_team, :integer
    field :usd_btc_icoend, :decimal
    field :usd_eth_icoend, :decimal
    belongs_to :project, Project
    many_to_many :currencies, Currency, join_through: "ico_currencies"
  end

  @doc false
  def changeset(%Ico{} = ico, attrs \\ %{}) do
    ico
    |> cast(attrs, [:start_date, :end_date, :tokens_issued_at_ico, :tokens_sold_at_ico, :tokens_team, :usd_btc_icoend, :funds_raised_btc, :usd_eth_icoend, :ico_contributors, :highest_bonus_percent_for_ico, :bounty_campaign, :percent_tokens_for_bounties, :minimal_cap_amount, :minimal_cap_archived, :maximal_cap_amount, :maximal_cap_archived, :project_id])
    |> validate_required([:project_id])
    |> unique_constraint(:project_id)
  end
end
