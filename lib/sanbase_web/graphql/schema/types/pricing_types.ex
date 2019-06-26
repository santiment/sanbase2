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

  object :subscription_plan do
    field(:id, :id)
    field(:user, :user)
    field(:plan, :plan)
    field(:current_period_end, :datetime)
  end

  object :subscription_cancellation do
    field(:scheduled_for_cancellation, :boolean)
    field(:scheduled_for_cancellation_at, :datetime)
  end
end
