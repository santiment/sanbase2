defmodule Sanbase.DeepResearch.Sessions.TurnCodec do
  @moduledoc """
  Converts between the in-memory `Sanbase.DeepResearch.Turn` struct and the
  `SessionTurn` row.

  Encoding is nearly free: Ecto/Jason stringify atom keys and values on write,
  and `phase` is an `Ecto.Enum`. All the real work is decoding — jsonb loads
  back string-keyed, but the components dot-access atom keys on timeline items,
  so each item kind is rebuilt through an explicit whitelist (never a blanket
  `String.to_atom`, which would both risk the atom table and wrongly atomize
  the genuinely dynamic nested maps: mcp `args`, chart `summary`/`series`,
  findings rows — those are string-keyed even in a live turn).
  """

  alias Sanbase.DeepResearch.Sessions.SessionTurn
  alias Sanbase.DeepResearch.Turn

  @doc "Row attrs for a `Turn`. `session_id`/`model_tier` are the caller's concern."
  @spec turn_to_attrs(Turn.t()) :: map()
  def turn_to_attrs(%Turn{} = turn) do
    %{
      position: turn.id,
      question: turn.question,
      report: turn.report,
      error: turn.error,
      clarification: turn.clarification || [],
      phase: turn.phase,
      timeline: turn.timeline,
      sources: turn.sources,
      started_at: ms_to_datetime(turn.started_at),
      finished_at: ms_to_datetime(turn.finished_at)
    }
  end

  @doc "Rebuild the renderable `Turn` struct from a loaded row."
  @spec from_row(SessionTurn.t()) :: Turn.t()
  def from_row(%SessionTurn{} = row) do
    %Turn{
      id: row.position,
      question: row.question,
      report: row.report,
      clarification: presence(row.clarification),
      started_at: datetime_to_ms(row.started_at),
      finished_at: datetime_to_ms(row.finished_at),
      error: row.error,
      phase: row.phase,
      timeline: row.timeline |> Enum.map(&decode_item/1) |> Enum.reject(&is_nil/1),
      sources: Enum.map(row.sources, &decode_source/1)
    }
  end

  defp ms_to_datetime(nil), do: nil
  defp ms_to_datetime(ms) when is_integer(ms), do: DateTime.from_unix!(ms, :millisecond)

  defp datetime_to_ms(nil), do: nil
  defp datetime_to_ms(%DateTime{} = dt), do: DateTime.to_unix(dt, :millisecond)

  defp presence([]), do: nil
  defp presence(list), do: list

  # -- timeline items ------------------------------------------------------------
  #
  # Item shapes mirror `Sanbase.DeepResearch.Timeline`'s moduledoc. Optional keys
  # (`count`, `results`, `args`, `ok`, `summary`, `done`, the status facts) are only
  # put back when present, because their *absence* is meaningful to the renderer
  # (e.g. a search without `count` reads as still running until `settle_item/1`
  # closes it).

  defp decode_item(%{"kind" => "thinking"} = m),
    do: %{kind: :thinking, id: m["id"], text: m["text"]}

  defp decode_item(%{"kind" => "search"} = m) do
    %{kind: :search, id: m["id"], query: m["query"]}
    |> maybe_put(:count, m["count"])
    |> maybe_put(:results, m["results"] && Enum.map(m["results"], &decode_result/1))
  end

  defp decode_item(%{"kind" => "mcp"} = m) do
    %{kind: :mcp, id: m["id"], tool: m["tool"]}
    |> maybe_put(:args, m["args"])
    |> maybe_put(:ok, m["ok"])
    |> maybe_put(:summary, m["summary"])
    |> maybe_put(:done, m["done"])
  end

  defp decode_item(%{"kind" => "fetch"} = m) do
    %{kind: :fetch, id: m["id"], url: m["url"]}
    |> maybe_put(:ok, m["ok"])
    |> maybe_put(:summary, m["summary"])
    |> maybe_put(:done, m["done"])
  end

  # Rows written before compaction had its own element stored it as a status row.
  defp decode_item(%{"kind" => "status", "state" => "compacted"} = m),
    do: decode_item(%{m | "kind" => "compaction"})

  defp decode_item(%{"kind" => "status"} = m) do
    %{kind: :status, state: m["state"], detail: m["detail"]}
    |> maybe_put(:reason, m["reason"])
    |> maybe_put(:repeats, m["repeats"])
    |> maybe_put(:attempt, m["attempt"])
  end

  defp decode_item(%{"kind" => "compaction"} = m) do
    %{kind: :compaction, state: m["state"]}
    |> maybe_put(:tokens_estimate, m["tokens_estimate"])
    |> maybe_put(:messages_summarized, m["messages_summarized"])
  end

  # The run's usage ledger: every field is optional (the agent only reports what it
  # measured), so absent ones stay absent.
  defp decode_item(%{"kind" => "usage"} = m) do
    %{kind: :usage}
    |> maybe_put(:elapsed_s, m["elapsed_s"])
    |> maybe_put(:tool_calls, m["tool_calls"])
    |> maybe_put(:model_calls, m["model_calls"])
    |> maybe_put(:total_tokens, m["total_tokens"])
    |> maybe_put(:cost_usd, m["cost_usd"])
    |> maybe_put(:subagent_runs, m["subagent_runs"])
  end

  defp decode_item(%{"kind" => "skill"} = m),
    do: %{kind: :skill, name: m["name"], path: m["path"]}

  defp decode_item(%{"kind" => "plan"} = m) do
    todos =
      m["todos"]
      |> List.wrap()
      |> Enum.filter(&is_map/1)
      |> Enum.map(
        &%{content: to_string(&1["content"] || ""), status: to_string(&1["status"] || "pending")}
      )

    %{kind: :plan, todos: todos}
  end

  defp decode_item(%{"kind" => "chart"} = m) do
    %{
      kind: :chart,
      id: m["id"],
      slug: m["slug"],
      range: m["range"],
      summary: m["summary"],
      series: m["series"] || []
    }
  end

  defp decode_item(%{"kind" => "subagent_findings"} = m) do
    %{
      kind: :subagent_findings,
      id: m["id"],
      unit: m["unit"],
      summary: m["summary"],
      findings: m["findings"] || [],
      gaps: m["gaps"] || []
    }
  end

  # A kind this release doesn't know (rolled-back deploy reading newer rows) —
  # drop the item rather than crash the whole transcript.
  defp decode_item(_unknown), do: nil

  defp decode_result(r),
    do: %{title: r["title"], url: r["url"], domain: r["domain"], snippet: r["snippet"]}

  defp decode_source(s), do: %{url: s["url"], title: s["title"], domain: s["domain"]}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
