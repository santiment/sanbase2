defmodule Sanbase.Repo.Migrations.CreateIcos do
  use Ecto.Migration

  def change do
    create table(:icos) do
      add :project_id, references(:project, on_delete: :delete_all), null: false
      add :start_date, :date
      add :end_date, :date
      add :tokens_issued_at_ico, :integer
      add :tokens_sold_at_ico, :integer
      add :tokens_team, :integer
      add :usd_btc_icoend, :decimal
      add :funds_raised_btc, :decimal
      add :usd_eth_icoend, :decimal
      add :ico_contributors, :integer
      add :highest_bonus_percent_for_ico, :decimal
      add :bounty_compaign, :boolean
      add :percent_tokens_for_bounties, :decimal
      add :minimal_cap_amount, :decimal
      add :minimal_cap_archived, :boolean
      add :maximal_cap_amount, :decimal
      add :maximal_cap_archived, :boolean
    end

    create unique_index(:icos, [:project_id])
  end
end
