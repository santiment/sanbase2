defmodule Sanbase.Repo.Migrations.AddFinishedObanJobsTable do
  use Ecto.Migration

  def change do
    create table(:finished_oban_jobs) do
      add(:queue, :string)
      add(:worker, :string)
      add(:args, :map)
      add(:inserted_at, :naive_datetime)
      add(:completed_at, :naive_datetime)
    end

    create_if_not_exists(index(:finished_oban_jobs, [:queue]))
    create_if_not_exists(index(:finished_oban_jobs, [:inserted_at]))
    create_if_not_exists(index(:finished_oban_jobs, [:args], using: :gin))

    execute("""
    CREATE OR REPLACE FUNCTION moveFinishedObanJobs(queue_arg character varying, limit_arg bigint) RETURNS bigint AS
     $BODY$
     DECLARE
       rows_count numeric;
     BEGIN
       WITH finished_job_ids_cte AS (
         SELECT id from oban_jobs
         WHERE queue = $1 AND completed_at IS NOT NULL
         LIMIT $2
       ),
       moved_rows AS (
         DELETE FROM oban_jobs a
         WHERE a.id IN (SELECT id FROM finished_job_ids_cte)
         RETURNING a.queue, a.worker, a.args, a.inserted_at, a.completed_at
       )
       INSERT INTO finished_oban_jobs(queue, worker, args, inserted_at, completed_at)
       SELECT * FROM moved_rows;

       GET DIAGNOSTICS rows_count = ROW_COUNT;
       RETURN rows_count;
     END;
     $BODY$
    LANGUAGE plpgsql;
    """)
  end

  def down do
    drop(table(:finished_oban_jobs))

    execute("""
    DROP FUNCTION IF EXISTS moveFinishedObanJobs;
    """)
  end
end
