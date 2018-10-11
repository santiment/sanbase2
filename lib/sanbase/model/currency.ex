defmodule Sanbase.Model.Currency do
  use Ecto.Schema
  import Ecto.Changeset

  import Ecto.Query, warn: false
  alias Sanbase.Repo

  alias Sanbase.Model.Currency

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
        get(currency_code)
        |> case do
          nil -> insert!(currency_code)
          currency -> currency
        end
      end)

    currency
  end
end

# used by ex_admin
defimpl String.Chars, for: Sanbase.Model.Currency do
  def to_string(term) do
    term.code
  end
end

# used by ex_admin
defimpl String.Chars, for: Sanbase.Model.Currency do
  def to_string(term) do
    term.code
  end
end
