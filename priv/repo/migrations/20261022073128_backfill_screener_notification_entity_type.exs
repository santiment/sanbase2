defmodule Sanbase.Repo.Migrations.BackfillScreenerNotificationEntityType do
  use Ecto.Migration

  @moduledoc """
  Screeners are watchlists with is_screener = true, so their app notifications
  were stored with entity_type 'watchlist'. New notifications get 'screener';
  this moves the existing ones over. Notifications whose watchlist was deleted
  cannot be resolved and keep 'watchlist'.
  """

  def up() do
    execute("""
    UPDATE sanbase_notifications n
    SET entity_type = 'screener'
    FROM user_lists ul
    WHERE n.entity_type = 'watchlist'
      AND n.entity_id = ul.id
      AND ul.is_screener
    """)
  end

  def down() do
    execute("""
    UPDATE sanbase_notifications
    SET entity_type = 'watchlist'
    WHERE entity_type = 'screener'
    """)
  end
end
