defmodule Sanbase.Seeds.ExchangeFundsFlowSeed do
  import Sanbase.Seeds.Helpers

  def populate() do
    changesets = [
      make_changeset(contract1(), random_date(), random_non_neg_float(), random_non_neg_float()),
      make_changeset(contract1(), random_date(), random_non_neg_float(), random_non_neg_float()),
      make_changeset(contract1(), random_date(), random_non_neg_float(), random_non_neg_float()),
      make_changeset(contract1(), random_date(), random_non_neg_float(), random_non_neg_float()),
      make_changeset(contract1(), random_date(), random_non_neg_float(), random_non_neg_float()),
      make_changeset(contract1(), random_date(), random_non_neg_float(), random_non_neg_float()),
      make_changeset(contract1(), random_date(), random_non_neg_float(), random_non_neg_float()),
      make_changeset(contract1(), random_date(), random_non_neg_float(), random_non_neg_float()),
      make_changeset(contract1(), random_date(), random_non_neg_float(), random_non_neg_float()),
      make_changeset(contract1(), random_date(), random_non_neg_float(), random_non_neg_float()),
      make_changeset(contract2(), random_date(), random_non_neg_float(), random_non_neg_float()),
      make_changeset(contract2(), random_date(), random_non_neg_float(), random_non_neg_float()),
      make_changeset(contract2(), random_date(), random_non_neg_float(), random_non_neg_float()),
      make_changeset(contract2(), random_date(), random_non_neg_float(), random_non_neg_float()),
      make_changeset(contract2(), random_date(), random_non_neg_float(), random_non_neg_float()),
      make_changeset(contract2(), random_date(), random_non_neg_float(), random_non_neg_float()),
      make_changeset(contract2(), random_date(), random_non_neg_float(), random_non_neg_float()),
      make_changeset(contract2(), random_date(), random_non_neg_float(), random_non_neg_float()),
      make_changeset(contract2(), random_date(), random_non_neg_float(), random_non_neg_float())
    ]

    Enum.map(changesets, &Sanbase.TimescaleRepo.insert/1)
  end

  defp make_changeset(contract, timestamp, inflow, outflow) do
    alias Sanbase.Blockchain.ExchangeFundsFlow

    %ExchangeFundsFlow{}
    |> ExchangeFundsFlow.changeset(%{
      contract_address: contract,
      timestamp: timestamp,
      incoming_exchange_funds: inflow,
      outgoing_exchange_funds: outflow
    })
  end
end
