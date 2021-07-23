defmodule Sanbase.Repo.Migrations.CreateIcos do
  use Ecto.Migration

  def change do
    create table(:icos) do
      add(:project_id, references(:project, on_delete: :delete_all), null: false)
      add(:start_date, :date)
      add(:end_date, :date)
      add(:tokens_issued_at_ico, :decimal)
      add(:tokens_sold_at_ico, :decimal)
      add(:funds_raised_btc, :decimal)
      add(:usd_btc_icoend, :decimal)
      add(:usd_eth_icoend, :decimal)
      add(:minimal_cap_amount, :decimal)
      add(:maximal_cap_amount, :decimal)
      add(:cap_currency_id, references(:currencies))
      add(:main_contract_address, :string)
      add(:comments, :text)
    end

    create(unique_index(:icos, [:project_id]))
  end
end
