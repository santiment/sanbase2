defmodule Sanbase.Repo.Migrations.AddNewFieldsCommentNotifications do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:comment_notifications) do
      add(:last_chart_configuration_comment_id, :integer)
      add(:last_watchlist_comment_id, :integer)
    end
  end
end
