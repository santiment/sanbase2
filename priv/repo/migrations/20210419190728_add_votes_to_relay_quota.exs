defmodule Sanbase.Repo.Migrations.AddVotesToRelayQuota do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:wallet_hunters_relays_quota) do
      add(:votes_used, :integer, default: 0)
      add(:last_voted, :utc_datetime)
      add(:proposals_earned, :integer, default: 0)
    end
  end
end
