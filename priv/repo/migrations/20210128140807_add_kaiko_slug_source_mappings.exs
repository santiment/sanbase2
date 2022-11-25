defmodule Sanbase.Repo.Migrations.AddKaikoSlugSourceMappings do
  use Ecto.Migration

  alias Sanbase.Project

  def up do
    slug_to_project_id_map =
      Enum.map(pairs(), &elem(&1, 1))
      |> Project.List.by_slugs()
      |> Map.new(fn %Project{slug: slug, id: id} -> {slug, id} end)

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    data =
      Enum.map(pairs(), fn {kaiko_code, santiment_slug} ->
        %{
          slug: kaiko_code,
          source: "kaiko",
          project_id: Map.get(slug_to_project_id_map, santiment_slug)
        }
      end)
      |> Enum.filter(& &1.project_id)

    Sanbase.Repo.insert_all(Project.SourceSlugMapping, data)
  end

  def down do
    :ok
  end

  def pairs do
    [
      {"btc", "bitcoin"},
      {"eth", "ethereum"},
      {"dot", "polkadot-new"},
      {"aave", "aave"},
      {"ada", "cardano"},
      {"ampl", "ampleforth"},
      {"bal", "balancer"},
      {"band", "band-protocol"},
      {"bat", "basic-attention-token"},
      {"bnb", "binance-coin"},
      {"comp", "compound"},
      {"dcr", "decred"},
      {"kava", "kava"},
      {"knc", "kyber-network"},
      {"link", "chainlink"},
      {"mkr", "maker"},
      {"omg", "omisego"},
      {"ren", "ren"},
      {"rep", "augur"},
      {"snx", "synthetix-network-token"},
      {"uni", "uniswap"},
      {"yfi", "yearn-finance"},
      {"sushi", "sushi"},
      {"zrx", "0x"},
      {"ocean", "ocean-protocol"}
    ]
  end
end
