defmodule Sanbase.Repo.Migrations.IcoMoveFundsRaisedTotalsToDetails do
  @moduledoc false
  use Ecto.Migration

  import Ecto.Query, warn: false

  alias Sanbase.Model.Currency
  alias Sanbase.Model.Ico
  alias Sanbase.Model.IcoCurrency
  alias Sanbase.Repo

  def up do
    usd = find_or_insert_currency("USD")
    eth = find_or_insert_currency("ETH")
    btc = find_or_insert_currency("BTC")
    currencies = %{usd: usd, eth: eth, btc: btc}

    from(
      i in Ico,
      preload: [ico_currencies: [:currency]],
      where:
        fragment(
          "NOT EXISTS(select 1
                  from ico_currencies ic
                  where ic.ico_id = ?
                        and ic.amount is not null)",
          i.id
        )
    )
    |> Repo.stream(max_rows: 10_000)
    |> Stream.each(fn ico ->
      ico_currency =
        try_from_existing_ico_currencies(ico, currencies) || try_from_totals(ico, currencies)

      if !is_nil(ico_currency) do
        Repo.insert_or_update!(ico_currency)
      end
    end)
    |> Enum.to_list()
  end

  defp try_from_existing_ico_currencies(ico, %{usd: usd, eth: eth, btc: btc}) do
    try_from_existing_ico_currency(ico, eth, ico.funds_raised_eth) ||
      try_from_existing_ico_currency(ico, btc, ico.funds_raised_btc) ||
      try_from_existing_ico_currency(ico, usd, ico.funds_raised_usd)
  end

  defp try_from_existing_ico_currency(ico, currency, funds_raised_total) do
    funds_raised_total &&
      ico.ico_currencies
      |> Enum.find(&(&1.currency_id == currency.id))
      |> case do
        nil -> nil
        ic -> IcoCurrency.changeset(ic, %{amount: funds_raised_total})
      end
  end

  defp try_from_totals(ico, %{usd: usd, eth: eth, btc: btc}) do
    try_from_total(ico, eth, ico.funds_raised_eth) ||
      try_from_total(ico, btc, ico.funds_raised_btc) ||
      try_from_total(ico, usd, ico.funds_raised_usd)
  end

  defp try_from_total(ico, currency, funds_raised_total) do
    case funds_raised_total do
      nil -> nil
      amount -> IcoCurrency.changeset(%IcoCurrency{}, %{ico_id: ico.id, currency_id: currency.id, amount: amount})
    end
  end

  defp find_or_insert_currency(currency_code) do
    Currency
    |> Repo.get_by(code: currency_code)
    |> case do
      result = %Currency{} ->
        result

      nil ->
        %Currency{}
        |> Currency.changeset(%{code: currency_code})
        |> Repo.insert!()
    end
  end

  def down do
  end
end
