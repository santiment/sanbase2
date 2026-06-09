# Add the "Funds" MarketSegment to a fixed list of project slugs.
#
# The script finds the "Funds" market segment, creating it if it does not yet
# exist, then links it to each project found by slug via the
# project_market_segments join table.
#
# Behavior:
#   - finds the "Funds" market segment, or creates it (name only, no type)
#   - if no project exists for a slug (e.g. on stage), report PROJECT_MISSING
#     and continue with the rest — does not raise
#   - if the segment is already linked, skip (idempotent; on_conflict: :nothing)
#
# Two ways to run:
#
#   1. As a script:
#        mix run scripts/seed_funds_market_segment.exs
#
#   2. Paste into iex:
#        Paste the whole `defmodule ... end` block, then call:
#        SeedFundsMarketSegment.run()

defmodule SeedFundsMarketSegment do
  import Ecto.Query

  alias Sanbase.Project
  alias Sanbase.Model.MarketSegment

  @segment_name "Funds"

  @slugs ~w(
    gbtc ibit fbtc arkb btco bitb hodl msbt brrr btc btcw ezbtc
    ethv ethw ezet qeth etha ethe feth teth eth
    bsol vsol fsol gsol soez
    bhyp thyp
  )

  def run(slugs \\ @slugs) do
    segment = fetch_or_create_segment!()

    projects_by_slug =
      slugs
      |> Project.List.by_slugs(preload?: true, preload: [:market_segments])
      |> Map.new(fn p -> {p.slug, p} end)

    results = Enum.map(slugs, &process_slug(&1, projects_by_slug, segment))

    insert_data =
      results
      |> Enum.filter(fn r -> r.status == :created end)
      |> Enum.map(fn %{project_id: id} -> %{project_id: id, market_segment_id: segment.id} end)

    Sanbase.Repo.insert_all(Project.ProjectMarketSegment, insert_data, on_conflict: :nothing)

    print_report(results, segment)

    %{results: results, summary: summarize(results)}
  end

  defp fetch_or_create_segment!() do
    case Sanbase.Repo.one(from(ms in MarketSegment, where: ms.name == ^@segment_name)) do
      %MarketSegment{} = segment ->
        IO.puts("FOUND segment #{inspect(@segment_name)} id=#{segment.id}")
        segment

      nil ->
        # Create the segment, ignoring a unique-name conflict from a concurrent
        # run, then re-fetch so we always return a persisted struct with an id.
        Sanbase.Repo.insert_all(MarketSegment, [%{name: @segment_name}], on_conflict: :nothing)
        segment = Sanbase.Repo.one!(from(ms in MarketSegment, where: ms.name == ^@segment_name))
        IO.puts("CREATED segment #{inspect(@segment_name)} id=#{segment.id}")
        segment
    end
  end

  defp process_slug(slug, projects_by_slug, segment) do
    case Map.get(projects_by_slug, slug) do
      nil ->
        %{status: :project_missing, slug: slug}

      %Project{id: project_id, market_segments: segments} ->
        if Enum.any?(segments, fn s -> s.id == segment.id end) do
          %{status: :skipped, slug: slug, project_id: project_id}
        else
          %{status: :created, slug: slug, project_id: project_id}
        end
    end
  end

  defp print_report(results, segment) do
    IO.puts("\n=== Add #{inspect(@segment_name)} (id=#{segment.id}) market segment ===")

    Enum.each(results, fn r -> IO.puts(format_result(r)) end)

    summary = summarize(results)

    summary_line =
      [:created, :skipped, :project_missing]
      |> Enum.map_join(" ", fn k -> "#{k}=#{Map.get(summary, k, 0)}" end)

    IO.puts("\nSummary: #{summary_line}")
  end

  defp summarize(results) do
    Enum.reduce(results, %{}, fn %{status: status}, acc ->
      Map.update(acc, status, 1, &(&1 + 1))
    end)
  end

  defp pad(s, n), do: String.pad_trailing(to_string(s), n)

  defp format_result(%{status: :created, slug: s, project_id: pid}),
    do: "CREATED          #{pad(s, 8)} project_id=#{pid}"

  defp format_result(%{status: :skipped, slug: s, project_id: pid}),
    do: "SKIP             #{pad(s, 8)} project_id=#{pid} (already linked)"

  defp format_result(%{status: :project_missing, slug: s}),
    do: "PROJECT_MISSING  #{pad(s, 8)} (no project for slug)"
end

# When loaded via `mix run`, kick it off. In iex, paste the defmodule block
# above and call SeedFundsMarketSegment.run() yourself (this line is harmless
# to paste too — it will run once).
SeedFundsMarketSegment.run()
