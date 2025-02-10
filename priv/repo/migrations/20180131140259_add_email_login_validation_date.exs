defmodule Sanbase.Repo.Migrations.AddEmailLoginValidationDate do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:email_token_validated_at, :naive_datetime)
    end
  end
end
