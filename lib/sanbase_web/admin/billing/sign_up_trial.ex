defmodule Sanbase.ExAdmin.Billing.SignUpTrial do
  use ExAdmin.Register

  register_resource Sanbase.Billing.Subscription.SignUpTrial do
    action_items(only: [:show, :edit])

    index do
      column(:user, fields: [:email, :username], link: true)

      column(:inserted_at)
      column(:updated_at)
    end

    show _product do
      attributes_table(all: true)
    end
  end
end
