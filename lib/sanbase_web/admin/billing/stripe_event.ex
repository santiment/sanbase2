defmodule SanbaseWeb.ExAdmin.Billing.StripeEvent do
  use ExAdmin.Register

  register_resource Sanbase.Billing.StripeEvent do
    action_items(only: [:show])

    index do
      column(:event_id)
      column(:type)
      column(:is_processed)
      column(:inserted_at)
    end

    show plan do
      attributes_table(all: true)
    end
  end
end
