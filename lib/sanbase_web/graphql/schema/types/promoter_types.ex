defmodule SanbaseWeb.Graphql.Schema.PromoterTypes do
  use Absinthe.Schema.Notation

  object :promoter do
    field(:email, :string)
    field(:earnings_balance, :integer)
    field(:current_balance, :integer)
    field(:paid_balance, :integer)
    field(:promotions, list_of(:promotion))
    field(:dashboard_url, :string)
  end

  object :promotion do
    field(:ref_id, :string)
    field(:referral_link, :string)
    field(:promo_code, :string)

    field(:visitors_count, :integer)
    field(:leads_count, :integer)
    field(:customers_count, :integer)
    field(:cancellations_count, :integer)
    field(:sales_count, :integer)
    field(:sales_total, :integer)
    field(:refunds_count, :integer)
    field(:refunds_total, :integer)
  end
end
