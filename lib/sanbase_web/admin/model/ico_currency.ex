defmodule Sanbase.ExAdmin.Model.IcoCurrency do
  use ExAdmin.Register

  import Ecto.Query, warn: false

  alias Sanbase.Model.{Ico, Currency, IcoCurrency}

  register_resource Sanbase.Model.IcoCurrency do
    index do
      selectable_column()

      column(:id)
      column(:ico)
      column(:amount)
      actions()
    end

    form ico_currencies do
      inputs do
        input(
          ico_currencies,
          :ico,
          collection: from(i in Ico, order_by: [desc: i.id]) |> Sanbase.Repo.all()
        )

        input(
          ico_currencies,
          :currency,
          collection: from(c in Currency, order_by: c.code) |> Sanbase.Repo.all()
        )

        input(ico_currencies, :amount)
      end
    end
  end
end
