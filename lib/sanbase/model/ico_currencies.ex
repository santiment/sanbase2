defmodule Sanbase.Model.IcoCurrencies do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.IcoCurrencies
  alias Sanbase.Model.Ico
  alias Sanbase.Model.Currency


  schema "ico_currencies" do
    belongs_to :ico, Ico
    belongs_to :currency, Currency, on_replace: :nilify
    field :value, :decimal
    field :_destroy, :boolean, virtual: true # used by ex_admin
  end

  @doc false
  def changeset(%IcoCurrencies{} = ico_currencies, attrs \\ %{}) do
    ico_currencies
    |> cast(attrs, [:ico_id, :currency_id, :value])
    |> validate_required([:ico_id, :currency_id])
    |> unique_constraint(:ico_currency, name: :ico_currencies_uk)
  end

  @doc false
  def changeset_ex_admin(%IcoCurrencies{} = ico_currencies, attrs \\ %{}) do
    attrs = set_currency_id(attrs)

    ico_currencies
    |> cast(attrs, [:ico_id, :currency_id, :value, :_destroy])
    |> validate_required([:currency_id])
    |> unique_constraint(:ico_currency, name: :ico_currencies_uk)
    |> mark_for_deletion()
  end

  # ex_admin stores the currency only by its code
  defp set_currency_id(attrs) do
    {currency_code, attrs} = Map.pop(attrs, :currency)

    currency_id = case currency_code do
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
