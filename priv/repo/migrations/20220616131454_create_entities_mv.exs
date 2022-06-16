defmodule Sanbase.Repo.Migrations.CreateEntitiesMv do
  use Ecto.Migration

  def up do
    Application.ensure_all_started(:timex)

    execute("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS entities
    AS
    SELECT
      *
    FROM (
    SELECT
      p.id as entity_id,
      'insight' as entity_type,
      p.user_id,
      coalesce(p.published_at, p.inserted_at) as created_at,
      p.is_deleted,
      p.is_hidden,
      CASE
      WHEN p.ready_state = 'published' AND p.state = 'approved'
        THEN true
      WHEN p.ready_state != 'published' OR p.state != 'approved'
        THEN false
      END is_public,
      COALESCE(comments_count, 0) as comments_count,
      COALESCE(voted_users_count, 0) as voted_users_count,
      COALESCE(votes_count, 0) as votes_count
    FROM posts as p
    LEFT JOIN (
      SELECT post_id, count(*) AS comments_count
      FROM post_comments_mapping
      GROUP BY post_id
    ) as pcm ON p.id = pcm.post_id
    LEFT JOIN (
      SELECT post_id, count(*) AS voted_users_count, sum(count) as votes_count
      FROM votes
      GROUP BY post_id
    ) as votes ON p.id = votes.post_id

    UNION

    SELECT
      cc.id as entity_id,
      'chart_configuration' as entity_type,
      cc.user_id,
      cc.inserted_at as created_at,
      cc.is_deleted,
      cc.is_hidden,
      cc.is_public,
      COALESCE(comments_count, 0) as comments_count,
      COALESCE(voted_users_count, 0) as voted_users_count,
      COALESCE(votes_count, 0) as votes_count
    FROM chart_configurations as cc
    LEFT JOIN (
      SELECT chart_configuration_id, count(*) AS comments_count
      FROM chart_configuration_comments_mapping
      GROUP BY chart_configuration_id
    ) as cccm ON cc.id = cccm.chart_configuration_id
    LEFT JOIN (
      SELECT chart_configuration_id, count(*) AS voted_users_count, sum(count) as votes_count
      FROM votes
      GROUP BY chart_configuration_id
    ) as votes ON cc.id = votes.chart_configuration_id

    UNION

    SELECT
      ul.id as entity_id,
      CASE
        WHEN ul.is_screener THEN 'screener'
        WHEN ul.type = 'project' THEN 'project_watchlist'
        WHEN ul.type = 'blockchain_address' THEN 'address_watchlist'
      END entity_type,
      ul.user_id,
      ul.inserted_at as created_at,
      ul.is_deleted,
      ul.is_hidden,
      ul.is_public,
      COALESCE(comments_count, 0) as comments_count,
      COALESCE(voted_users_count, 0) as voted_users_count,
      COALESCE(votes_count, 0) as votes_count
    FROM user_lists as ul
    LEFT JOIN (
      SELECT watchlist_id, count(*) AS comments_count
      FROM watchlist_comments_mapping
      GROUP BY watchlist_id
    ) as wcm ON ul.id = wcm.watchlist_id
    LEFT JOIN (
      SELECT watchlist_id, count(*) AS voted_users_count, sum(count) as votes_count
      FROM votes
      GROUP BY watchlist_id
    ) as votes ON ul.id = votes.watchlist_id

    UNION

    SELECT
      ut.id as entity_id,
      'user_trigger' as entity_type,
      ut.user_id,
      ut.inserted_at as created_at,
      ut.is_deleted,
      ut.is_hidden,
      trigger->>'is_public' = 'true' as is_public,
      0 as comments_count,
      COALESCE(voted_users_count, 0) as voted_users_count,
      COALESCE(votes_count, 0) as votes_count
    FROM user_triggers as ut
    LEFT JOIN (
      SELECT user_trigger_id, count(*) AS voted_users_count, sum(count) as votes_count
      FROM votes
      GROUP BY user_trigger_id
    ) as votes ON ut.id = votes.user_trigger_id
    ) as foo

    WITH DATA;
    """)
  end

  def down do
    Application.ensure_all_started(:timex)

    execute("""
    DROP MATERIALIZED VIEW entities;
    """)
  end
end
