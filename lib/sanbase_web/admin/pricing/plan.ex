defmodule Sanbase.ExAdmin.Pricing.Plan do
  use ExAdmin.Register

  register_resource Sanbase.Pricing.Plan do
    action_items(only: [:show])

    index do
      column(:id)
      column(:name)
      column(:amount)
      column(:currency)
      column(:interval)
      column(:stripe_id)
      column(:product)
    end

    show _plan do
      attributes_table(all: true)
    end
  end
end
