defmodule SanbaseWeb.Graphql.Schema.BillingTypes do
  use Absinthe.Schema.Notation

  enum :billing_status do
    value(:initial)
    value(:incomplete)
    value(:incomplete_expired)
    value(:trialing)
    value(:active)
    value(:past_due)
    value(:canceled)
    value(:unpaid)
  end

  enum :promo_email_lang_enum do
    value(:en)
    value(:jp)
  end

  object :product do
    field(:id, :id)
    field(:name, :string)
    field(:plans, list_of(:plan))
  end

  object :plan do
    field(:id, :id)
    field(:name, :string)
    field(:product, :product)
    field(:interval, :string)
    field(:amount, :integer)
  end

  object :subscription_plan do
    field(:id, :id)
    field(:user, :user)
    field(:plan, :plan)
    field(:current_period_end, :datetime)
    field(:cancel_at_period_end, :boolean)
    field(:status, :billing_status)
    field(:trial_end, :datetime)
  end

  object :subscription_cancellation do
    field(:is_scheduled_for_cancellation, :boolean)
    field(:scheduled_for_cancellation_at, :datetime)
  end

  object :payments do
    field(:receipt_url, :string)
    field(:amount, :integer)
    field(:created_at, :datetime)
    field(:status, :string)
    field(:description, :string)
  end

  object :send_coupon_success do
    field(:success, non_null(:boolean))
  end
end
