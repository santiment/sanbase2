defmodule SanbaseWeb.Graphql.Resolvers.IcoResolver do
  require Logger

  import Ecto.Query, warn: false

  alias Sanbase.Model.Ico
  alias Sanbase.Model.Currency

  alias Sanbase.Repo

  def cap_currency(%Ico{cap_currency_id: nil}, _args, _resolution), do: {:ok, nil}
  def cap_currency(%Ico{cap_currency_id: cap_currency_id}, _args, _resolution) do
    %Currency{code: currency_code} = Repo.get!(Currency, cap_currency_id)

    {:ok, currency_code}
  end

  def currency_amounts(%Ico{id: id}, _args, _resolution) do
    query = from i in Ico,
    left_join: ic in assoc(i, :ico_currencies),
    inner_join: c in assoc(ic, :currency),
    where: i.id == ^id,
    select: %{currency_code: c.code, amount: ic.amount}

    currency_amounts = Repo.all(query)

    {:ok, currency_amounts}
  end

  def funds_raised_usd_ico_end_price(%Ico{} = ico, _args, _resolution) do
    result = Ico.funds_raised_usd_ico_end_price(ico)

    {:ok, result}
  end

  def funds_raised_eth_ico_end_price(%Ico{} = ico, _args, _resolution) do
    result = Ico.funds_raised_eth_ico_end_price(ico)

    {:ok, result}
  end

  def funds_raised_btc_ico_end_price(%Ico{} = ico, _args, _resolution) do
    result = Ico.funds_raised_btc_ico_end_price(ico)

    {:ok, result}
  end

  defp requested_fields(resolution) do
    resolution.definition.selections
    |> Enum.map(&(Map.get(&1, :name) |> String.to_atom()))
    |> Enum.into(%{}, fn field -> {field, true} end)
  end
end
