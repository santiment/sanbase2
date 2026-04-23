defmodule SanbaseWeb.GenericAdmin.Plan do
  @behaviour SanbaseWeb.GenericAdmin
  def schema_module, do: Sanbase.Billing.Plan
  def resource_name, do: "plans"
  def singular_resource_name, do: "plan"

  def resource do
    %{
      preloads: [:product],
      index_fields: [
        :id,
        :product_id,
        :name,
        :amount,
        :currency,
        :interval,
        :stripe_id,
        :is_deprecated,
        :is_private,
        :order
      ],
      edit_fields: [:name, :amount, :stripe_id, :is_deprecated, :is_private, :order],
      actions: [:edit],
      fields_override: %{
        product_id: %{
          value_modifier: &SanbaseWeb.GenericAdmin.Product.product_link/1
        },
        restrictions: %{
          value_modifier: fn plan ->
            if(plan.restrictions,
              do: Map.from_struct(plan.restrictions) |> Jason.encode!(),
              else: ""
            )
          end
        }
      }
    }
  end
end
