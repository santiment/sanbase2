defmodule SanbaseWeb.Graphql.Resolvers.IcoResolver do
  require Logger

  import Ecto.Query, warn: false
  import Absinthe.Resolution.Helpers

  alias Sanbase.Model.Ico
  alias Sanbase.Model.Currency

  alias Sanbase.Repo

  def cap_currency(%Ico{cap_currency_id: nil}, _args, _resolution), do: {:ok, nil}
  def cap_currency(%Ico{cap_currency_id: cap_currency_id}, _args, _resolution) do
    batch({__MODULE__, :currencies_by_id}, cap_currency_id, fn batch_results ->
      {:ok, Map.get(batch_results, cap_currency_id)}
    end)
  end
  def currencies_by_id(_, currency_ids) do
    currencies = from(i in Currency,
    where: i.id in ^currency_ids)
    |> Repo.all()

    Map.new(currencies, fn currency -> {currency.id, currency.code} end)
  end

  def currency_amounts(%Ico{id: id}, _args, _resolution) do
    batch({__MODULE__, :currency_amounts_by_id}, id, fn batch_results ->
      {:ok, Map.get(batch_results, id)}
    end)
  end
  def currency_amounts_by_id(_, ico_ids) do
    query = from i in Ico,
    left_join: ic in assoc(i, :ico_currencies),
    inner_join: c in assoc(ic, :currency),
    where: i.id in ^ico_ids,
    select: %{ico_id: i.id, currency_code: c.code, amount: ic.amount}

    Repo.all(query)
    |> Enum.group_by(&(&1.ico_id), &(%{currency_code: &1.currency_code, amount: &1.amount}))
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
