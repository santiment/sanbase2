defmodule Sanbase.Repo.Migrations.FillIsSubscribedWeeklyNewsletter do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE user_settings
    SET settings = jsonb_set(
        settings,
        '{is_subscribed_weekly_newsletter}',
        settings->'is_subscribed_monthly_newsletter'
    )
    WHERE (settings->>'is_subscribed_weekly_newsletter') IS DISTINCT FROM (settings->>'is_subscribed_monthly_newsletter')
    """)
  end

  def down do
    :ok
  end
end
