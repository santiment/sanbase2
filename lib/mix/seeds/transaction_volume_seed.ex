defmodule Sanbase.Seeds.TransactionVolumeSeed do
  import Sanbase.Seeds.Helpers

  def populate() do
    changesets = [
      make_changeset(contract1(), random_date(), random_non_neg_float()),
      make_changeset(contract1(), random_date(), random_non_neg_float()),
      make_changeset(contract1(), random_date(), random_non_neg_float()),
      make_changeset(contract1(), random_date(), random_non_neg_float()),
      make_changeset(contract1(), random_date(), random_non_neg_float()),
      make_changeset(contract1(), random_date(), random_non_neg_float()),
      make_changeset(contract1(), random_date(), random_non_neg_float()),
      make_changeset(contract1(), random_date(), random_non_neg_float()),
      make_changeset(contract1(), random_date(), random_non_neg_float()),
      make_changeset(contract1(), random_date(), random_non_neg_float()),
      make_changeset(contract2(), random_date(), random_non_neg_float()),
      make_changeset(contract2(), random_date(), random_non_neg_float()),
      make_changeset(contract2(), random_date(), random_non_neg_float()),
      make_changeset(contract2(), random_date(), random_non_neg_float()),
      make_changeset(contract2(), random_date(), random_non_neg_float()),
      make_changeset(contract2(), random_date(), random_non_neg_float()),
      make_changeset(contract2(), random_date(), random_non_neg_float()),
      make_changeset(contract2(), random_date(), random_non_neg_float()),
      make_changeset(contract2(), random_date(), random_non_neg_float())
    ]

    Enum.map(changesets, &Sanbase.TimescaleRepo.insert/1)
  end

  defp make_changeset(contract, timestamp, transaction_volume) do
    alias Sanbase.Blockchain.TransactionVolume

    %TransactionVolume{}
    |> TransactionVolume.changeset(%{
      contract_address: contract,
      timestamp: timestamp,
      transaction_volume: transaction_volume
    })
  end
end
