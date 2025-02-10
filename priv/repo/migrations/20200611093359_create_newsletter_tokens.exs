defmodule Sanbase.Repo.Migrations.CreateNewsletterTokens do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:newsletter_tokens) do
      add(:token, :string)
      add(:email, :string)
      add(:email_token_generated_at, :utc_datetime)
      add(:email_token_validated_at, :utc_datetime)

      timestamps()
    end

    create(unique_index(:newsletter_tokens, [:email, :token], name: :email_token_uk))
  end
end
