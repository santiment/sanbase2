defmodule SanbaseWeb.ExAdmin.Billing.Subscription do
  use ExAdmin.Register

  register_resource Sanbase.Billing.Subscription do
    action_items(only: [:show, :edit, :test])

    query do
      %{
        all: [preload: [:user, plan: [:product]]]
      }
    end

    index do
      column(:id, link: true)
      column(:stripe_id)
      column(:status)
      column(:current_period_end)
      column(:trial_end)
      column(:cancel_at_period_end)
      column(:user, fields: [:email, :username], link: true)
      column(:plan, link: true)

      column("Product", fn subscription ->
        subscription.plan.product.name
      end)

      column(:inserted_at)
      column(:updated_at)
    end

    show subscription do
      attributes_table do
        row(:id)
        row(:stripe_id)
        row(:status)
        row(:current_period_end)
        row(:trial_end)
        row(:cancel_at_period_end)
        row(:user, fields: [:email, :username], link: true)
        row(:plan, link: true)

        row("Product", fn subscription ->
          subscription.plan.product.name
        end)

        row(:inserted_at)
        row(:updated_at)
      end
    end
  end
end
