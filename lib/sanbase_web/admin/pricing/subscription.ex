defmodule Sanbase.ExAdmin.Pricing.Subscription do
  use ExAdmin.Register

  register_resource Sanbase.Pricing.Subscription do
    action_items(only: [:new, :show, :edit])

    show _subscription do
      attributes_table(all: true)
    end
  end
end
