defmodule Sanbase.Repo.Migrations.AddEnabledAtToFeatureToggles do
  use Ecto.Migration

  # `enabled_at` records when a toggle was last turned on. The
  # `business_reduced_api_calls` toggle uses it as the cutoff: Business PRO / MAX
  # subscriptions created after it get the reduced monthly API call allowance,
  # older ones are grandfathered. See Sanbase.ApiCallLimit.BusinessAllowance.
  #
  # The new toggle row is inserted disabled, so deploying this changes nothing.
  def up() do
    alter table(:feature_toggles) do
      add(:enabled_at, :utc_datetime)
    end

    flush()

    execute("""
    INSERT INTO feature_toggles (name, enabled, inserted_at, updated_at)
    VALUES ('business_reduced_api_calls', false, now(), now())
    ON CONFLICT (name) DO NOTHING
    """)
  end

  def down() do
    execute("DELETE FROM feature_toggles WHERE name = 'business_reduced_api_calls'")

    alter table(:feature_toggles) do
      remove(:enabled_at)
    end
  end
end
