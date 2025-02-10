defmodule Sanbase.Model.IcoCurrency do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Model.Currency
  alias Sanbase.Model.Ico
  alias Sanbase.Model.IcoCurrency

  schema "ico_currencies" do
    belongs_to(:ico, Ico)
    belongs_to(:currency, Currency, on_replace: :nilify)
    field(:amount, :decimal)
    field(:_destroy, :boolean, virtual: true)
  end

  @doc false
  def changeset(%IcoCurrency{} = ico_currencies, attrs \\ %{}) do
    ico_currencies
    |> cast(attrs, [:ico_id, :currency_id, :amount])
    |> validate_required([:ico_id, :currency_id])
    |> unique_constraint(:ico_currency, name: :ico_currencies_uk)
  end
end
