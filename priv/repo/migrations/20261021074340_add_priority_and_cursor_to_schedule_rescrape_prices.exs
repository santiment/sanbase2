defmodule Sanbase.Repo.Migrations.AddPriorityAndCursorToScheduleRescrapePrices do
  use Ecto.Migration

  @table :schedule_rescrape_prices
  @active_index_name :schedule_rescrape_prices_one_active_per_project_index

  def up() do
    alter table(@table) do
      add(:priority, :string, null: false, default: "normal")
      add(:status, :string, null: false, default: "pending")
      # The rescrape's own cursor. Rescrapes no longer move the shared
      # price_scraping_progress row of the regular scraper.
      add(:progress_datetime, :naive_datetime)
      add(:last_error, :text)
      add(:started_at, :naive_datetime)
      add(:finished_at, :naive_datetime)

      # The legacy flags are no longer used. With these defaults the rows
      # inserted by the new code are invisible to the old code while both
      # versions run during a rolling deploy (the old code only looks at rows
      # with finished = false).
      modify(:in_progress, :boolean, null: false, default: false)
      modify(:finished, :boolean, null: false, default: true)
    end

    flush()

    execute("""
    UPDATE schedule_rescrape_prices
    SET status = 'finished', finished_at = updated_at
    WHERE finished = true
    """)

    execute("""
    UPDATE schedule_rescrape_prices
    SET status = 'running', started_at = updated_at
    WHERE in_progress = true AND finished = false
    """)

    # The rescrapes in progress have moved the shared progress row. Copy that
    # position to the rescrape's own cursor...
    execute("""
    UPDATE schedule_rescrape_prices s
    SET progress_datetime = psp.datetime
    FROM project p, price_scraping_progress psp
    WHERE s.status = 'running'
      AND p.id = s.project_id
      AND psp.identifier = p.slug
      AND psp.source = 'coinmarketcap'
    """)

    # ...and give the shared progress row back to the regular scraper. If there
    # are multiple running rescrapes for a project, the first one holds the
    # real original_last_updated value.
    execute("""
    UPDATE price_scraping_progress psp
    SET datetime = s.original_last_updated, updated_at = now()
    FROM schedule_rescrape_prices s, project p
    WHERE s.id = (
        SELECT min(s2.id) FROM schedule_rescrape_prices s2
        WHERE s2.project_id = s.project_id AND s2.status = 'running'
      )
      AND s.original_last_updated IS NOT NULL
      AND p.id = s.project_id
      AND psp.identifier = p.slug
      AND psp.source = 'coinmarketcap'
    """)

    # Keep only the newest active rescrape per project so the unique index can be built
    execute("""
    UPDATE schedule_rescrape_prices s
    SET status = 'cancelled',
        last_error = 'Cancelled by migration: a newer rescrape for the same project exists',
        finished_at = now()
    WHERE s.status IN ('pending', 'running')
      AND EXISTS (
        SELECT 1 FROM schedule_rescrape_prices s2
        WHERE s2.project_id = s.project_id
          AND s2.status IN ('pending', 'running')
          AND s2.id > s.id
      )
    """)

    execute("UPDATE schedule_rescrape_prices SET in_progress = false, finished = true")

    create(
      unique_index(@table, [:project_id],
        name: @active_index_name,
        where: "status IN ('pending', 'running')"
      )
    )

    # Not validated, as some old rows have from > to
    create(constraint(@table, :from_before_to, check: ~s("from" < "to"), validate: false))
  end

  def down() do
    drop(constraint(@table, :from_before_to))
    drop(index(@table, [:project_id], name: @active_index_name))

    alter table(@table) do
      remove(:priority)
      remove(:status)
      remove(:progress_datetime)
      remove(:last_error)
      remove(:started_at)
      remove(:finished_at)

      modify(:in_progress, :boolean, null: false, default: nil)
      modify(:finished, :boolean, null: false, default: nil)
    end
  end
end
