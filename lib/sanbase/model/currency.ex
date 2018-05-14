defmodule Sanbase.Model.Currency do
  use Ecto.Schema
  import Ecto.Changeset

  import Ecto.Query, warn: false
  alias Sanbase.Repo

  alias Sanbase.Model.{
    Currency,
    Project
  }

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

  @doc ~s"""
    Return a project with a matching ticker. `Repo.one` fails if there are more
    than one project with the same ticker.
  """
  @spec to_project(%Currency{}) :: %Project{} | no_return()
  def to_project(%Currency{code: code}) do
    from(
      p in Sanbase.Model.Project,
      where: p.ticker == ^code and not is_nil(p.coinmarketcap_id)
    )
    |> Repo.one()
  end
end

# used by ex_admin
defimpl String.Chars, for: Sanbase.Model.Currency do
  def to_string(term) do
    term.code
  end
end
