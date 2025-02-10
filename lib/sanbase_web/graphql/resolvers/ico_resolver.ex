defmodule SanbaseWeb.Graphql.Resolvers.IcoResolver do
  @moduledoc false
  import Absinthe.Resolution.Helpers
  import Ecto.Query, warn: false

  alias Sanbase.Model.Currency
  alias Sanbase.Model.Ico

  require Logger

  def cap_currency(%Ico{cap_currency_id: nil}, _args, _resolution), do: {:ok, nil}

  def cap_currency(%Ico{cap_currency_id: cap_currency_id}, _args, _resolution) do
    batch({__MODULE__, :currencies_by_id}, cap_currency_id, fn batch_results ->
      {:ok, Map.get(batch_results, cap_currency_id)}
    end)
  end

  def currencies_by_id(_, currency_ids) do
    currency_ids
    |> Currency.by_ids()
    |> Map.new(fn currency -> {currency.id, currency.code} end)
  end

  def funds_raised(%Ico{id: id}, _args, _resolution) do
    batch({__MODULE__, :funds_raised_by_id}, id, fn batch_results ->
      {:ok, Map.get(batch_results, id)}
    end)
  end

  def funds_raised_by_id(_, ico_ids) do
    ico_ids
    |> Ico.funds_raised_by_icos()
    |> Enum.group_by(& &1.ico_id, &%{currency_code: &1.currency_code, amount: &1.amount})
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
end
