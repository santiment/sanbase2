defmodule Sanbase.Model.IcoCurrencies do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.IcoCurrencies
  alias Sanbase.Model.Ico
  alias Sanbase.Model.Currency


  @primary_key false
  schema "ico_currencies" do
    belongs_to :ico, Ico
    belongs_to :currency, Currency, foreign_key: :currency_code, references: :code
  end

  @doc false
  def changeset(%IcoCurrencies{} = ico_currencies, attrs \\ %{}) do
    ico_currencies
    |> cast(attrs, [])
    |> validate_required([])
  end
end
