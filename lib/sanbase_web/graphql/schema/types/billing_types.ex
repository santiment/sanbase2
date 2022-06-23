defmodule SanbaseWeb.Graphql.BillingTypes do
  use Absinthe.Schema.Notation

  enum :restriction_types_enum do
    value(:free)
    value(:restricted)
    value(:custom)
    value(:all)
  end

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
    field(:interval, :interval)
    field(:amount, :integer)
    field(:is_deprecated, :boolean)
    field(:is_private, :boolean)
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

  object :coupon do
    field(:is_valid, :boolean)
    field(:id, :string)
    field(:name, :string)
    field(:amount_off, :float)
    field(:percent_off, :float)
  end

  object :upcoming_invoice do
    field(:period_start, non_null(:datetime))
    field(:period_end, non_null(:datetime))
    field(:amount_due, non_null(:integer))
  end

  object :payment_instrument do
    field(:last4, non_null(:string))
    field(:dynamic_last4, :string)
    field(:brand, non_null(:string))
    field(:funding, :string)
    field(:exp_year, non_null(:integer))
    field(:exp_month, non_null(:integer))
  end

  object :annual_discount_eligibility do
    field(:is_eligible, non_null(:boolean))
    field(:discount, :annual_discount)
  end

  object :annual_discount do
    field(:percent_off, non_null(:integer))
    field(:expire_at, non_null(:datetime))
  end
end
