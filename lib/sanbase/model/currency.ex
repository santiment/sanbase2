defmodule Sanbase.Model.Currency do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Model.Currency
  alias Sanbase.Repo

  schema "currencies" do
    field(:code, :string)
  end

  @doc false
  def changeset(%Currency{} = currency, attrs \\ %{}) do
    currency
    |> cast(attrs, [:code])
    |> validate_required([:code])
    |> unique_constraint(:code)
  end

  def by_ids(ids) do
    Repo.all(from(i in __MODULE__, where: i.id in ^ids))
  end

  def get(currency_code) do
    Repo.get_by(Currency, code: currency_code)
  end

  def insert!(currency_code) do
    %Currency{}
    |> Currency.changeset(%{code: currency_code})
    |> Repo.insert!()
  end

  def get_or_insert(currency_code) do
    {:ok, currency} =
      Repo.transaction(fn ->
        currency_code
        |> get()
        |> case do
          nil -> insert!(currency_code)
          currency -> currency
        end
      end)

    currency
  end
end

defimpl String.Chars, for: Sanbase.Model.Currency do
  def to_string(term) do
    term.code
  end
end
