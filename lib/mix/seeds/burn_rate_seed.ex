defmodule Sanbase.Seeds.BurnRateSeed do
  def populate() do
    changesets = [
      burn_rate_changeset("0x123123", random_date(), random_non_neg_float()),
      burn_rate_changeset("0x123123", random_date(), random_non_neg_float()),
      burn_rate_changeset("0x123123", random_date(), random_non_neg_float()),
      burn_rate_changeset("0x123123", random_date(), random_non_neg_float()),
      burn_rate_changeset("0x123123", random_date(), random_non_neg_float()),
      burn_rate_changeset("0x543210", random_date(), random_non_neg_float()),
      burn_rate_changeset("0x543210", random_date(), random_non_neg_float()),
      burn_rate_changeset("0x543210", random_date(), random_non_neg_float()),
      burn_rate_changeset("0x543210", random_date(), random_non_neg_float()),
      burn_rate_changeset("0x543210", random_date(), random_non_neg_float()),
      burn_rate_changeset("0x543210", random_date(), random_non_neg_float())
    ]

    Enum.map(changesets, &Sanbase.TimescaleRepo.insert/1)
  end

  defp burn_rate_changeset(contract, timestamp, burn_rate) do
    alias Sanbase.Blockchain.BurnRate

    %BurnRate{}
    |> BurnRate.changeset(%{
      contract_address: contract,
      timestamp: timestamp,
      burn_rate: burn_rate
    })
  end

  def random_date(days \\ 90) do
    day_shift = :rand.uniform(days)

    Timex.now()
    |> Timex.shift(days: -day_shift)
  end

  def random_non_neg_float(upper_limit \\ 10_000) do
    :rand.uniform() * upper_limit
  end
end
