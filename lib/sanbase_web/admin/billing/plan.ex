defmodule Sanbase.ExAdmin.Billing.Plan do
  use ExAdmin.Register

  register_resource Sanbase.Billing.Plan do
    action_items(only: [:show, :edit])

    index do
      column(:id)
      column(:name)
      column(:amount)
      column(:currency)
      column(:interval)
      column(:stripe_id)
      column(:product)
    end

    form plan do
      inputs do
        input(plan, :name)
        input(plan, :amount)
        input(plan, :stripe_id)
      end
    end

    show _plan do
      attributes_table(all: true)
    end
  end
end
