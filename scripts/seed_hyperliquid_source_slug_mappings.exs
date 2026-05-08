# Seed Sanbase.Project.SourceSlugMapping rows for the Hyperliquid BBO scraper.
#
# Each entry is a {hl_coin, sanbase_slug} pair. A row is inserted with
# source = "hyperliquid" and slug = the HL coin, linked to the project found
# by the Sanbase slug.
#
# Behavior:
#   - if no project exists for a slug (e.g. on stage), report PROJECT_MISSING
#     and continue with the rest — does not raise
#   - if mapping already matches, skip
#   - if a different mapping exists for (project, source), report
#     EXISTS_DIFFERENT_MAPPING (one mapping per project+source is enforced;
#     remove the old row first to change it)
#
# Two ways to run:
#
#   1. As a script:
#        mix run scripts/seed_hyperliquid_source_slug_mappings.exs
#
#   2. Paste into iex:
#        Paste the whole `defmodule ... end` block, then call:
#        SeedHyperliquidSourceSlugMappings.run()

defmodule SeedHyperliquidSourceSlugMappings do
  alias Sanbase.Project
  alias Sanbase.Project.SourceSlugMapping

  @source "hyperliquid"

  @mappings [
    {"HYPE", "hyperliquid"},
    {"ONDO", "ondo-finance"},
    {"BTC", "bitcoin"},
    {"ZEC", "zcash"},
    {"TAO", "bittensor"},
    {"XRP", "xrp"},
    {"SOL", "solana"},
    {"DOGE", "dogecoin"},
    {"ETH", "ethereum"},
    {"BNB", "binance-coin"},
    {"PENGU", "pudgy-penguins"},
    {"ALGO", "algorand"},
    # {"MANA", "decentraland"}, # not supported
    {"LTC", "litecoin"},
    {"ADA", "cardano"},
    {"XMR", "monero"},
    {"ZRO", "layerzero"},
    {"AAVE", "aave"},
    {"ATOM", "cosmos"},
    {"LINK", "chainlink"},
    {"AVAX", "avalanche"},
    # on Hyperliquid it's kPEPE
    {"kPEPE", "pepe"},
    {"DASH", "dash"},
    # {"ENJ", "enjin-coin"}, # not supported
    {"SUI", "sui"},
    {"NEAR", "near-protocol"},
    {"USELESS", "theuselesscoin"},
    {"UNI", "uniswap"},
    {"BCH", "bitcoin-cash"},
    {"PUMP", "sol-pump-fun"},
    # {"TON", "toncoin"},
    {"JTO", "jito"}
  ]

  def run(mappings \\ @mappings) do
    {deduped, duplicates} = validate_and_dedupe(mappings)

    slugs = Enum.map(deduped, fn {_, slug} -> slug end)
    projects_by_slug = Sanbase.Project.List.by_slugs(slugs) |> Map.new(fn p -> {p.slug, p} end)

    results = Enum.map(deduped, &process_entry(&1, projects_by_slug))

    print_report(results, duplicates)

    %{
      results: results,
      duplicates: duplicates,
      summary: summarize(results)
    }
  end

  defp validate_and_dedupe(mappings) do
    {deduped, dups} =
      Enum.reduce(mappings, {[], []}, fn entry, {acc, dups} ->
        case entry do
          {coin, slug} when is_binary(coin) and is_binary(slug) ->
            if Enum.any?(acc, fn {c, s} -> c == coin and s == slug end) do
              {acc, [{coin, slug} | dups]}
            else
              {acc ++ [{coin, slug}], dups}
            end

          other ->
            raise "Invalid mapping entry: #{inspect(other)} (expected {coin, slug} binary tuple)"
        end
      end)

    {deduped, Enum.reverse(dups)}
  end

  defp process_entry({coin, slug}, projects_by_slug) do
    case Map.get(projects_by_slug, slug) do
      nil ->
        %{status: :project_missing, coin: coin, slug: slug}

      %Project{id: project_id} = project ->
        process_existing_project(coin, slug, project, project_id)
    end
  end

  defp process_existing_project(coin, slug, project, project_id) do
    case SourceSlugMapping.get_slug(project, @source) do
      ^coin ->
        %{status: :skipped, coin: coin, slug: slug, project_id: project_id}

      other when is_binary(other) ->
        %{
          status: :exists_different_mapping,
          coin: coin,
          slug: slug,
          project_id: project_id,
          existing_coin: other
        }

      nil ->
        insert_mapping(coin, slug, project_id)
    end
  end

  defp insert_mapping(coin, slug, project_id) do
    case SourceSlugMapping.create(%{source: @source, slug: coin, project_id: project_id}) do
      {:ok, ssm} ->
        %{status: :created, coin: coin, slug: slug, project_id: project_id, ssm_id: ssm.id}

      {:error, changeset} ->
        %{
          status: :errored,
          coin: coin,
          slug: slug,
          project_id: project_id,
          error: inspect(changeset.errors)
        }
    end
  end

  defp print_report(results, duplicates) do
    IO.puts("\n=== Hyperliquid source_slug_mappings seed ===")

    Enum.each(results, fn r -> IO.puts(format_result(r)) end)

    if duplicates != [] do
      pairs = Enum.map_join(duplicates, ", ", fn {c, s} -> "{#{c},#{s}}" end)
      IO.puts("\nIgnored duplicate entries: #{pairs}")
    end

    summary = summarize(results)

    summary_line =
      [:created, :skipped, :exists_different_mapping, :project_missing, :errored]
      |> Enum.map_join(" ", fn k -> "#{k}=#{Map.get(summary, k, 0)}" end)

    IO.puts("\nSummary: #{summary_line}")
  end

  defp summarize(results) do
    Enum.reduce(results, %{}, fn %{status: status}, acc ->
      Map.update(acc, status, 1, &(&1 + 1))
    end)
  end

  defp pad(s, n), do: String.pad_trailing(to_string(s), n)

  defp format_result(%{status: :created, coin: c, slug: s, project_id: pid, ssm_id: id}),
    do: "CREATED   #{pad(c, 10)} -> #{pad(s, 25)} project_id=#{pid} ssm_id=#{id}"

  defp format_result(%{status: :skipped, coin: c, slug: s, project_id: pid}),
    do: "SKIP      #{pad(c, 10)} -> #{pad(s, 25)} project_id=#{pid} (mapping exists)"

  defp format_result(%{
         status: :exists_different_mapping,
         coin: c,
         slug: s,
         project_id: pid,
         existing_coin: existing
       }),
       do:
         "EXISTS_DIFFERENT_MAPPING  #{pad(c, 10)} -> #{pad(s, 25)} project_id=#{pid} (already mapped to #{inspect(existing)}; remove first to change)"

  defp format_result(%{status: :project_missing, coin: c, slug: s}),
    do: "PROJECT_MISSING  #{pad(c, 10)} -> #{pad(s, 25)} (no project for slug)"

  defp format_result(%{status: :errored, coin: c, slug: s, project_id: pid, error: err}),
    do: "ERROR     #{pad(c, 10)} -> #{pad(s, 25)} project_id=#{pid} #{err}"
end

# When loaded via `mix run`, kick it off. In iex, paste the defmodule block
# above and call SeedHyperliquidSourceSlugMappings.run() yourself (this line
# is harmless to paste too — it will run once).
SeedHyperliquidSourceSlugMappings.run()
