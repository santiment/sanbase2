defmodule Sanbase.DeepResearch.Sessions.TurnCodecTest do
  @moduledoc """
  The codec's contract: a `Turn` written as row attrs and read back through the
  jsonb round trip (string keys!) must decode to the identical struct, and that
  decoded struct must render through `turn_view/1` — the components dot-access
  atom keys, so any drift in the whitelist raises here, not in production.
  """

  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Sanbase.DeepResearch.Sessions.{SessionTurn, TurnCodec}
  alias Sanbase.DeepResearch.Turn

  # Covers every timeline item kind plus sources. The nested dynamic maps (mcp
  # args, chart summary/series, findings rows) are string-keyed on purpose —
  # they are string-keyed in a live turn too.
  defp full_turn() do
    %Turn{
      id: 1,
      question: "What is driving ETH?",
      report: "## Findings\n\nFees fell.",
      clarification: nil,
      started_at: 1_754_820_000_000,
      finished_at: 1_754_820_090_000,
      error: nil,
      phase: :completed,
      timeline: [
        %{kind: :thinking, id: "m1", text: "Scanning on-chain data"},
        %{
          kind: :search,
          id: "s1",
          query: "eth gas fees",
          count: 1,
          results: [
            %{
              title: "Gas report",
              url: "https://example.com/gas",
              domain: "example.com",
              snippet: "fees fell"
            }
          ]
        },
        %{
          kind: :mcp,
          id: "c1",
          tool: "fetch_metric",
          args: %{"metric" => "gas_used_5m"},
          ok: true,
          summary: "42 rows",
          done: true
        },
        %{kind: :status, state: "mcp_ready", detail: nil},
        %{kind: :skill, name: "charting", path: "skills/charting"},
        %{
          kind: :chart,
          id: "ch1",
          slug: "ethereum",
          range: "90d",
          summary: %{"last" => 12.5},
          series: [%{"label" => "Gas used", "data" => [1, 2]}]
        },
        %{
          kind: :subagent_findings,
          unit: "eth-onchain",
          summary: "Activity up",
          findings: [
            %{"finding" => "Fees fell", "evidence" => "30% drop", "source" => "santiment"}
          ],
          gaps: ["no L2 data"]
        }
      ],
      sources: [%{url: "https://example.com/gas", title: "Gas report", domain: "example.com"}]
    }
  end

  # What Postgres does to a jsonb column: atom keys/values become strings.
  defp jsonb_round_trip(value), do: value |> Jason.encode!() |> Jason.decode!()

  defp store_and_load(%Turn{} = turn) do
    attrs = TurnCodec.turn_to_attrs(turn)

    row = %SessionTurn{
      position: attrs.position,
      question: attrs.question,
      report: attrs.report,
      error: attrs.error,
      clarification: attrs.clarification,
      # Ecto.Enum loads the atom back itself; the jsonb columns do not.
      phase: attrs.phase,
      timeline: jsonb_round_trip(attrs.timeline),
      sources: jsonb_round_trip(attrs.sources),
      started_at: attrs.started_at,
      finished_at: attrs.finished_at
    }

    TurnCodec.from_row(row)
  end

  test "a turn with every timeline kind survives the round trip unchanged" do
    turn = full_turn()

    assert store_and_load(turn) == turn
  end

  test "the decoded turn renders through turn_view/1" do
    decoded = store_and_load(full_turn())

    html =
      render_component(&SanbaseWeb.DeepResearch.Components.turn_view/1,
        turn: decoded,
        running: false
      )

    assert html =~ "What is driving ETH?"
    assert html =~ "Fees fell."
    assert html =~ "eth gas fees"
    assert html =~ "fetch_metric"
    assert html =~ "charting"
    assert html =~ "Gas used"
    assert html =~ "30% drop"
  end

  test "a clarification turn round-trips ([] loads back as nil-less list)" do
    turn = %Turn{
      id: 2,
      question: "Which chains?",
      clarification: ["Which time range?", "Spot or derivatives?"],
      started_at: 1_754_820_000_000,
      finished_at: 1_754_820_005_000,
      phase: :awaiting_user
    }

    assert store_and_load(turn) == turn
  end

  test "an empty clarification column decodes to nil, matching a live turn" do
    turn = %Turn{id: 3, question: "q", started_at: 1, finished_at: 2, phase: :completed}

    decoded = store_and_load(turn)

    assert decoded.clarification == nil
    assert decoded == turn
  end

  test "optional in-flight keys stay absent so settle_item/1 semantics survive" do
    turn = %Turn{
      id: 4,
      question: "q",
      started_at: 1,
      finished_at: 2,
      phase: :failed,
      error: "boom",
      timeline: [
        # A search that never got results and an mcp call that never returned.
        %{kind: :search, id: "s1", query: "pending"},
        %{kind: :mcp, id: "c1", tool: "fetch_metric"}
      ]
    }

    decoded = store_and_load(turn)

    assert decoded == turn
    refute Map.has_key?(Enum.at(decoded.timeline, 0), :count)
    refute Map.has_key?(Enum.at(decoded.timeline, 1), :done)

    # And a terminal turn with such items must render settled (no spinner).
    html =
      render_component(&SanbaseWeb.DeepResearch.Components.turn_view/1,
        turn: decoded,
        running: false
      )

    refute html =~ "loading-spinner"
  end

  test "an unknown timeline kind is dropped instead of crashing the transcript" do
    row = %SessionTurn{
      position: 5,
      question: "q",
      phase: :completed,
      clarification: [],
      timeline: [
        %{"kind" => "hologram", "data" => "??"},
        %{"kind" => "thinking", "id" => "m1", "text" => "hi"}
      ],
      sources: [],
      started_at: DateTime.from_unix!(1, :millisecond),
      finished_at: DateTime.from_unix!(2, :millisecond)
    }

    decoded = TurnCodec.from_row(row)

    assert [%{kind: :thinking, id: "m1", text: "hi"}] = decoded.timeline
  end
end
