defmodule Sanbase.Repo.Migrations.DropTablesOfRemovedFeatures do
  use Ecto.Migration

  # Drop the tables (and the columns pointing to them) of features whose code
  # has already been removed: wallet hunters, timeline events, the old dashboards
  # implementation, PPP (geoip_data), the discord bot GPT router, pumpkins,
  # sign up trials, project transparency, promo coupons, questionnaires, etc.
  #
  # Everything uses IF EXISTS as some of these tables were already dropped
  # manually on some databases (e.g. eth_coin_circulation).

  @tables [
    # timeline events
    :seen_timeline_events,
    :timeline_event_comments_mapping,
    :timeline_events,
    # wallet hunters
    :wallet_hunters_proposals_comments_mapping,
    :wallet_hunters_votes,
    :wallet_hunters_relays_quota,
    :wallet_hunters_proposals,
    :wallet_hunters_bounties,
    # old dashboards implementation
    :dashboards_history,
    :discord_dashboards,
    # misc
    :comment_notifications,
    :eth_coin_circulation,
    :geoip_data,
    :gpt_router,
    :posts_projects,
    :price_migration_tmp,
    :project_transparency_statuses,
    :promo_coupons,
    :pumpkins,
    :sign_up_trials,
    :thread_ai_context,
    # questionnaires
    :questionnaire_answers,
    :questionnaire_questions,
    :questionnaires
  ]

  def up do
    # votes.timeline_event_id is part of the only_one_fk check that requires
    # exactly one vote target. The votes on timeline events have no other target,
    # so they are deleted before the column is removed from the check.
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = current_schema()
          AND table_name = 'votes'
          AND column_name = 'timeline_event_id'
      ) THEN
        DELETE FROM votes WHERE timeline_event_id IS NOT NULL;
      END IF;
    END
    $$;
    """)

    execute("ALTER TABLE votes DROP CONSTRAINT IF EXISTS only_one_fk")
    execute("ALTER TABLE votes DROP COLUMN IF EXISTS timeline_event_id")

    fk_check = """
    CASE WHEN post_id IS NULL THEN 0 ELSE 1 END +
    CASE WHEN chart_configuration_id IS NULL THEN 0 ELSE 1 END +
    CASE WHEN watchlist_id IS NULL THEN 0 ELSE 1 END +
    CASE WHEN user_trigger_id IS NULL THEN 0 ELSE 1 END +
    CASE WHEN dashboard_id IS NULL THEN 0 ELSE 1 END +
    CASE WHEN query_id IS NULL THEN 0 ELSE 1 END = 1
    """

    create(constraint(:votes, :only_one_fk, check: fk_check))

    execute("ALTER TABLE project DROP COLUMN IF EXISTS project_transparency_status_id")
    execute("ALTER TABLE project DROP COLUMN IF EXISTS project_transparency_description")
    execute("ALTER TABLE project DROP COLUMN IF EXISTS project_transparency")

    # Leftovers of the old dashboards implementation
    execute("ALTER TABLE dashboards DROP COLUMN IF EXISTS panels")
    execute("ALTER TABLE dashboards_cache DROP COLUMN IF EXISTS panels")

    for table <- @tables do
      execute("DROP TABLE IF EXISTS #{table}")
    end

    # Used only by promo_coupons
    execute("DROP TYPE IF EXISTS lang")
    # Used only by questionnaire_questions
    execute("DROP TYPE IF EXISTS question_type")
  end

  def down do
    require Logger

    Logger.warning("""
    Rolling back #{inspect(__MODULE__)} does not restore anything. The dropped
    tables, columns and their data cannot be restored by a rollback. Restore them
    from a backup if needed.
    """)
  end
end
