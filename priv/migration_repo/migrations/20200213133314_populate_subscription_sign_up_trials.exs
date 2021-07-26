defmodule Sanbase.Repo.Migrations.PopulateSubscriptionSignUpTrials do
  use Ecto.Migration

  alias Sanbase.Billing.Subscription.SignUpTrial
  alias Sanbase.Billing.{Subscription, Product}
  alias Sanbase.Accounts.User

  alias Sanbase.Repo

  def up do
    setup()

    SignUpTrial
    |> Repo.all()
    |> Enum.each(fn sign_up_trial ->
      user = Repo.get(User, sign_up_trial.user_id)
      current_subscription = Subscription.current_subscription(user, Product.product_sanbase())

      if current_subscription do
        SignUpTrial.changeset(sign_up_trial, %{subscription_id: current_subscription.id})
        |> Repo.update()
      end
    end)
  end

  def down do
    :ok
  end

  defp setup do
    Application.ensure_all_started(:tzdata)
    Application.ensure_all_started(:prometheus_ecto)
    Sanbase.Prometheus.EctoInstrumenter.setup()
  end
end
