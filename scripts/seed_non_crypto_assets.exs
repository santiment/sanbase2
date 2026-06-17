# Seed Sanbase.NonCryptoAsset rows and their Hyperliquid source slug mappings.
#
# Each entry creates (if missing):
#   1. a `non_crypto_assets` row identified by `slug`
#   2. a `source_slug_mappings` row with source = "hyperliquid" and
#      slug = the HL coin name, linked to the non-crypto asset
#
# NOTE: Verify the HL `coin` values against the live Hyperliquid meta API
# (POST https://api.hyperliquid.xyz/info {"type":"meta"}) before running —
# the names below are placeholders for the non-crypto markets.
#
# Does NOT run on load — the @assets coin names are placeholders that must be
# verified against the live Hyperliquid meta API (above) first. Run it
# explicitly once verified, two ways:
#
#   1. As a script:
#        mix run -e "SeedNonCryptoAssets.run()" scripts/seed_non_crypto_assets.exs
#
#   2. Paste into iex:
#        Paste the whole `defmodule ... end` block, then call:
#        SeedNonCryptoAssets.run()

defmodule SeedNonCryptoAssets do
  alias Sanbase.NonCryptoAsset
  alias Sanbase.Project.SourceSlugMapping

  @source "hyperliquid"

  @assets [
    %{coin: "GOLD", slug: "gold", name: "Gold", ticker: "XAU", asset_type: :commodity},
    %{coin: "SILVER", slug: "silver", name: "Silver", ticker: "XAG", asset_type: :commodity},
    %{coin: "SPX", slug: "sp500", name: "S&P 500", ticker: "SPX", asset_type: :index}
  ]

  def run(assets \\ @assets) do
    results = Enum.map(assets, &process_entry/1)

    IO.puts("\n=== Non-crypto assets seed ===")
    Enum.each(results, fn r -> IO.puts(format_result(r)) end)

    summary =
      Enum.reduce(results, %{}, fn %{status: status}, acc ->
        Map.update(acc, status, 1, &(&1 + 1))
      end)

    IO.puts("\nSummary: #{inspect(summary)}")

    %{results: results, summary: summary}
  end

  defp process_entry(%{coin: coin, slug: slug} = entry) do
    with {:ok, asset} <- get_or_create_asset(entry),
         {:ok, status} <- ensure_mapping(coin, asset) do
      %{status: status, coin: coin, slug: slug, asset_id: asset.id}
    else
      {:error, error} ->
        %{status: :errored, coin: coin, slug: slug, error: inspect(error)}
    end
  end

  defp get_or_create_asset(%{slug: slug} = entry) do
    case NonCryptoAsset.by_slug(slug) do
      nil -> NonCryptoAsset.create(Map.delete(entry, :coin))
      asset -> {:ok, asset}
    end
  end

  defp ensure_mapping(coin, asset) do
    case SourceSlugMapping.get_source_slug(asset.slug, @source) do
      ^coin ->
        {:ok, :skipped}

      nil ->
        case SourceSlugMapping.create(%{
               source: @source,
               slug: coin,
               non_crypto_asset_id: asset.id
             }) do
          {:ok, _} -> {:ok, :created}
          {:error, changeset} -> {:error, changeset.errors}
        end

      other ->
        {:error, "already mapped to #{inspect(other)}; remove the old mapping first"}
    end
  end

  defp format_result(%{status: :errored, coin: c, slug: s, error: err}),
    do: "ERROR    #{c} -> #{s} #{err}"

  defp format_result(%{status: status, coin: c, slug: s, asset_id: id}),
    do:
      "#{status |> to_string() |> String.upcase() |> String.pad_trailing(8)} #{c} -> #{s} asset_id=#{id}"
end

# Intentionally not invoked on load — see the header note. Run explicitly with
# `mix run -e "SeedNonCryptoAssets.run()" scripts/seed_non_crypto_assets.exs`.
