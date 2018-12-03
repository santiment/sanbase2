defmodule Sanbase.Seeds.TokenCirculationSeed do
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

  defp make_changeset(contract, timestamp, token_circulation) do
    alias Sanbase.Blockchain.TokenCirculation

    %TokenCirculation{}
    |> TokenCirculation.changeset(%{
      contract_address: contract,
      timestamp: timestamp,
      less_than_a_day: token_circulation
    })
  end
end
