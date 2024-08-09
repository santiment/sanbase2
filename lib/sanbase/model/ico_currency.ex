defmodule Sanbase.Model.IcoCurrency do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.IcoCurrency
  alias Sanbase.Model.Ico
  alias Sanbase.Model.Currency

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

  defp set_currency_id(attrs) do
    {currency_code, attrs} = Map.pop(attrs, :currency)

    currency_id =
      case currency_code do
        nil -> nil
        c -> Sanbase.Repo.get_by(Currency, code: c)
      end
      |> case do
        %Currency{id: id} -> id
        _ -> nil
      end

    Map.put(attrs, :currency_id, currency_id)
  end

  defp mark_for_deletion(changeset) do
    if get_change(changeset, :_destroy) do
      %{changeset | action: :delete}
    else
      changeset
    end
  end
end
