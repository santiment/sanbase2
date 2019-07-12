defmodule Sanbase.ExAdmin.Pricing.StripeEvent do
  use ExAdmin.Register

  register_resource Sanbase.Pricing.StripeEvent do
    action_items(only: [:show])

    index do
      column(:event_id)
      column(:type)
      column(:is_processed)
      column(:inserted_at)
    end

    show _plan do
      attributes_table(all: true)
    end
  end
end
