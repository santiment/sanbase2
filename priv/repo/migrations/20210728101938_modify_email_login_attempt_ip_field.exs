defmodule Sanbase.Repo.Migrations.ModifyEmailLoginAttemptIpField do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:email_login_attempts) do
      modify(:ip_address, :string, size: 39)
    end
  end
end
