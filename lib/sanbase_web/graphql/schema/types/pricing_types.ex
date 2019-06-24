defmodule SanbaseWeb.Graphql.Schema.PricingTypes do
  use Absinthe.Schema.Notation

  object :product do
    field(:name, :string)
    field(:plans, list_of(:plan))
  end

  object :plan do
    field(:id, :id)
    field(:name, :string)
    field(:access, :json)
    field(:product, :product)
    field(:interval, :string)
    field(:amount, :integer)
  end

  object :plan_subscription do
    field(:plan, :plan)
  end
end
