defmodule Sanbase.Seeds.BurnRateSeed do
  import Sanbase.Seeds.Helpers

  def populate() do
    changesets = [
      make_changeset("0x123123", random_date(), random_non_neg_float()),
      make_changeset("0x123123", random_date(), random_non_neg_float()),
      make_changeset("0x123123", random_date(), random_non_neg_float()),
      make_changeset("0x123123", random_date(), random_non_neg_float()),
      make_changeset("0x123123", random_date(), random_non_neg_float()),
      make_changeset("0x123123", random_date(), random_non_neg_float()),
      make_changeset("0x123123", random_date(), random_non_neg_float()),
      make_changeset("0x123123", random_date(), random_non_neg_float()),
      make_changeset("0x543210", random_date(), random_non_neg_float()),
      make_changeset("0x543210", random_date(), random_non_neg_float()),
      make_changeset("0x543210", random_date(), random_non_neg_float()),
      make_changeset("0x543210", random_date(), random_non_neg_float()),
      make_changeset("0x543210", random_date(), random_non_neg_float()),
      make_changeset("0x543210", random_date(), random_non_neg_float()),
      make_changeset("0x543210", random_date(), random_non_neg_float()),
      make_changeset("0x543210", random_date(), random_non_neg_float()),
      make_changeset("0x543210", random_date(), random_non_neg_float())
    ]

    Enum.map(changesets, &Sanbase.TimescaleRepo.insert/1)
  end

  defp make_changeset(contract, timestamp, burn_rate) do
    alias Sanbase.Blockchain.BurnRate

    %BurnRate{}
    |> BurnRate.changeset(%{
      contract_address: contract,
      timestamp: timestamp,
      burn_rate: burn_rate
    })
  end
end
