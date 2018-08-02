defmodule Sanbase.Seeds.DailyActiveAddressesSeed do
  import Sanbase.Seeds.Helpers

  def populate() do
    changesets = [
      make_changeset("0x123123", random_date(), random_non_neg_integer()),
      make_changeset("0x123123", random_date(), random_non_neg_integer()),
      make_changeset("0x123123", random_date(), random_non_neg_integer()),
      make_changeset("0x123123", random_date(), random_non_neg_integer()),
      make_changeset("0x123123", random_date(), random_non_neg_integer()),
      make_changeset("0x123123", random_date(), random_non_neg_integer()),
      make_changeset("0x123123", random_date(), random_non_neg_integer()),
      make_changeset("0x123123", random_date(), random_non_neg_integer()),
      make_changeset("0x543210", random_date(), random_non_neg_integer()),
      make_changeset("0x543210", random_date(), random_non_neg_integer()),
      make_changeset("0x543210", random_date(), random_non_neg_integer()),
      make_changeset("0x543210", random_date(), random_non_neg_integer()),
      make_changeset("0x543210", random_date(), random_non_neg_integer()),
      make_changeset("0x543210", random_date(), random_non_neg_integer()),
      make_changeset("0x543210", random_date(), random_non_neg_integer()),
      make_changeset("0x543210", random_date(), random_non_neg_integer()),
      make_changeset("0x543210", random_date(), random_non_neg_integer())
    ]

    Enum.map(changesets, &Sanbase.TimescaleRepo.insert/1)
  end

  defp make_changeset(contract, timestamp, active_addresses) do
    alias Sanbase.Blockchain.DailyActiveAddresses

    %DailyActiveAddresses{}
    |> DailyActiveAddresses.changeset(%{
      contract_address: contract,
      timestamp: timestamp,
      active_addresses: active_addresses
    })
  end
end
