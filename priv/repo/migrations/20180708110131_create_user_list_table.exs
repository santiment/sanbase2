defmodule Sanbase.Repo.Migrations.CreateUserListTable do
  use Ecto.Migration

  @table_name :user_lists
  def up do
    ColorEnum.create_type()

    create table(@table_name) do
      add(:name, :string)
      add(:is_public, :bool, default: false)
      add(:color, :color)
      add(:user_id, references(:users, on_delete: :delete_all))
      timestamps()
    end
  end

  def down do
    drop(table(:user_lists))
    ColorEnum.drop_type()
  end
end
