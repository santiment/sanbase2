defmodule SanbaseWeb.ExAdmin.Billing.PromoTrial do
  use ExAdmin.Register

  alias Sanbase.Repo
  alias Sanbase.Accounts.User
  alias Sanbase.Billing.Plan
  alias Sanbase.Billing.Subscription.PromoTrial

  register_resource PromoTrial do
    form promo_trial do
      inputs do
        input(
          promo_trial,
          :user,
          collection: Repo.all(User),
          fields: [:email, :username]
        )

        input(promo_trial, :trial_days)
      end

      inputs "Plans" do
        inputs(:plans,
          as: :check_boxes,
          collection:
            PromoTrial.promo_trial_plans()
            |> Enum.map(&Plan.by_id/1)
            |> Enum.map(&Map.put(&1, :name, &1.product.name <> " / " <> &1.name))
        )
      end
    end

    show promo_trial do
      attributes_table(all: true)
    end

    controller do
      after_filter(:create_promo_trials, only: [:create])
    end
  end

  def create_promo_trials(conn, params, resource, :create) do
    {:ok, _} = Sanbase.Billing.Subscription.PromoTrial.create_promo_trial(params.promo_trial)
    {conn, params, resource}
  end
end
