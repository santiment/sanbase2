defmodule Sanbase.Repo.Migrations.AddUserIdToPostImages do
  use Ecto.Migration

  def up do
    unless column_exists?(:post_images, :user_id) do
      alter table(:post_images) do
        add(:user_id, references(:users), null: true)
      end
    end
  end

  def down do
    alter table(:post_images) do
      remove(:user_id)
    end
  end

  defp column_exists?(table, column) do
    query = """
    SELECT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name = '#{table}' AND column_name = '#{column}'
    )
    """

    %{rows: [[exists]]} = repo().query!(query)
    exists
  end
end
