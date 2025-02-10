defmodule Sanbase.Repo.Migrations.UpdateAlertLimitsPerDay do
  @moduledoc false
  use Ecto.Migration

  def up do
    setup()

    # Update alerts_per_day_limit for email, those with values over 200 are set to 200
    execute("""
    UPDATE user_settings
    SET settings = jsonb_set(settings, '{alerts_per_day_limit, email}', '200')
    WHERE (settings -> 'alerts_per_day_limit' ->> 'email')::int > 200;
    """)

    # Update alerts_per_day_limit for telegram, those with values over 1000 are set to 1000
    execute("""
    UPDATE user_settings
    SET settings = jsonb_set(settings, '{alerts_per_day_limit, telegram}', '1000')
    WHERE (settings -> 'alerts_per_day_limit' ->> 'telegram')::int > 1000;
    """)
  end

  def down do
    :ok
  end

  defp setup do
    Application.ensure_all_started(:tzdata)
  end
end
