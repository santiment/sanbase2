defmodule Sanbase.Repo.Migrations.PopulateSubscriptionSignUpTrials do
  @moduledoc false
  use Ecto.Migration

  alias Sanbase.Accounts.User
  alias Sanbase.Billing.Product
  alias Sanbase.Billing.Subscription
  alias Sanbase.Repo

  def up do
    setup()
    :ok
  end

  def down do
    :ok
  end

  defp setup do
    Application.ensure_all_started(:tzdata)
  end
end
