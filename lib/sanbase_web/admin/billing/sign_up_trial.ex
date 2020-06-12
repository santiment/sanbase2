defmodule SanbaseWeb.ExAdmin.Billing.SignUpTrial do
  use ExAdmin.Register

  register_resource Sanbase.Billing.Subscription.SignUpTrial do
    action_items(only: [:show, :edit, :delete])

    index do
      column(:user, fields: [:email, :username], link: true)
      column(:subscription, link: true)
      column(:is_finished)
      column(:inserted_at)
      column(:updated_at)
    end

    show product do
      attributes_table(all: true)
    end
  end
end
