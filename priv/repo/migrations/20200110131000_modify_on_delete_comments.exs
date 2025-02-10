defmodule Sanbase.Repo.Migrations.ModifyOnDeleteComments do
  @moduledoc false
  use Ecto.Migration

  @table "comments"
  def up do
    execute("ALTER TABLE #{@table} DROP CONSTRAINT comments_parent_id_fkey")
    execute("ALTER TABLE #{@table} DROP CONSTRAINT comments_root_parent_id_fkey")

    alter table(@table) do
      modify(:parent_id, references(:comments, on_delete: :delete_all))
      modify(:root_parent_id, references(:comments, on_delete: :delete_all))
    end
  end

  def down do
    execute("ALTER TABLE #{@table} DROP CONSTRAINT comments_parent_id_fkey")
    execute("ALTER TABLE #{@table} DROP CONSTRAINT comments_root_parent_id_fkey")

    alter table(@table) do
      modify(:parent_id, references(:comments, on_delete: :nothing))
      modify(:root_parent_id, references(:comments, on_delete: :nothing))
    end
  end
end
