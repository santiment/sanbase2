defmodule Sanbase.Repo.Migrations.CreateEmailListConsents do
  use Ecto.Migration

  @moduledoc """
  An append-only record of when and where a user subscribed to or unsubscribed
  from a consent-based email list, kept as evidence of the consent.

  `users.newsletter_opt_in_pending` holds a newsletter signup from a website form
  until the user verifies the email address with the link sent to it.
  """

  def change() do
    create table(:email_list_consents) do
      add(:user_id, references(:users, on_delete: :delete_all), null: false)
      add(:list, :string, null: false)
      add(:subscribed, :boolean, null: false)
      add(:source, :string, null: false)

      timestamps(updated_at: false)
    end

    create(index(:email_list_consents, [:user_id, :list]))

    alter table(:users) do
      add(:newsletter_opt_in_pending, :boolean, null: false, default: false)
    end
  end
end
