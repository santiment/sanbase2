defmodule SanbaseWeb.ExAdmin.Billing.SanBurnCreditTransaction do
  use ExAdmin.Register

  register_resource Sanbase.Billing.Subscription.SanBurnCreditTransaction do
    action_items(only: [:show])
  end
end
