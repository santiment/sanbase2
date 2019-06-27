defmodule Sanbase.ExAdmin.Pricing.Subscription do
  use ExAdmin.Register

  register_resource Sanbase.Pricing.Subscription do
    action_items(only: [:show])

    show _subscription do
      attributes_table(all: true)
    end
  end
end
