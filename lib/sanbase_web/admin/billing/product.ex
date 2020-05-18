defmodule Sanbase.ExAdmin.Billing.Product do
  use ExAdmin.Register

  register_resource Sanbase.Billing.Product do
    action_items(only: [:show])

    show product do
      attributes_table(all: true)
    end
  end
end
