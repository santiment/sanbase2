defmodule Sanbase.ExAdmin.Pricing.Product do
  use ExAdmin.Register

  register_resource Sanbase.Pricing.Product do
    action_items(only: [:show])

    show _product do
      attributes_table(all: true)
    end
  end
end
