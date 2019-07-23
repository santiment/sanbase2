defmodule Sanbase.ExAdmin.Billing.Subscription do
  use ExAdmin.Register

  register_resource Sanbase.Billing.Subscription do
    action_items(only: [:new, :show, :edit])

    show _subscription do
      attributes_table(all: true)
    end
  end
end
