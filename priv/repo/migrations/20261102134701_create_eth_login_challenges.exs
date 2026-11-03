defmodule Sanbase.Repo.Migrations.CreateEthLoginChallenges do
  use Ecto.Migration

  # One-time messages for wallet login, see Sanbase.Accounts.EthLoginChallenge.
  # Also inserts the `eth_login_legacy` toggle row (enabled) so the admin panel
  # can switch the old fixed-message wallet login off.
  def up() do
    create table(:eth_login_challenges) do
      add(:address, :string, null: false)
      add(:nonce, :string, null: false)
      add(:message, :text, null: false)
      add(:expires_at, :utc_datetime, null: false)
      add(:used_at, :utc_datetime)

      timestamps()
    end

    create(unique_index(:eth_login_challenges, [:nonce]))
    create(index(:eth_login_challenges, [:address]))
    create(index(:eth_login_challenges, [:expires_at]))

    execute("""
    INSERT INTO feature_toggles (name, enabled, inserted_at, updated_at)
    VALUES ('eth_login_legacy', true, now(), now())
    ON CONFLICT (name) DO NOTHING
    """)
  end

  # Keep the toggle row on rollback, so the admin's setting survives a re-run.
  def down() do
    drop(table(:eth_login_challenges))
  end
end
