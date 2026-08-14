defmodule SanbaseWeb.DeepResearch.ComponentsTest do
  @moduledoc """
  Render tests for the deep research presentation layer.

  These render the components directly (no LiveView mount, no auth, no DB) — the
  point is to prove the HEEx actually renders for every kind of timeline item and
  every phase, which compilation alone does not.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import SanbaseWeb.DeepResearch.Components

  alias Sanbase.DeepResearch.Timeline

  @now 1_700_000_000_000

  defp turn(results, overrides \\ %{}) do
    "What is driving ETH?"
    |> Timeline.new_turn(1, @now)
    |> then(&Enum.reduce(results, &1, fn result, acc -> Timeline.apply_result(acc, result) end))
    |> Map.merge(overrides)
  end

  defp render_turn(turn, opts \\ []) do
    render_component(&turn_view/1,
      turn: turn,
      running: Keyword.get(opts, :running, false),
      now_ms: Keyword.get(opts, :now_ms),
      can_continue: Keyword.get(opts, :can_continue, false)
    )
  end

  describe "composer/1" do
    test "renders the question textarea and a submit button when idle" do
      html = render_component(&composer/1, query: "eth", running: false, placeholder: "Ask…")

      assert html =~ "Ask…"
      assert html =~ "eth"
      refute html =~ "phx-click=\"cancel\""
    end

    test "offers a cancel affordance while a run is in flight" do
      html = render_component(&composer/1, query: "", running: true, placeholder: "Ask…")

      assert html =~ "phx-click=\"cancel\""
    end
  end

  describe "turn_view/1" do
    test "always shows the question" do
      assert render_turn(turn([])) =~ "What is driving ETH?"
    end

    test "renders thinking narration" do
      html = render_turn(turn([%{thinking: %{id: "m1", text: "Planning the research"}}]))

      assert html =~ "Planning the research"
    end

    test "a paused turn shows the pause footer even with an empty timeline" do
      html = render_turn(turn([], %{phase: :paused, finished_at: @now + 5_000}))

      assert html =~ "Research paused"
      # Not the owner's resumable view — no Continue button.
      refute html =~ "phx-click=\"continue_turn\""
      refute html =~ "loading-spinner"
    end

    test "a continuable paused turn offers the Continue button" do
      html =
        render_turn(
          turn([%{thinking: %{id: "m1", text: "Scanning"}}], %{
            phase: :paused,
            finished_at: @now + 5_000
          }),
          can_continue: true
        )

      assert html =~ "Research paused"
      assert html =~ "phx-click=\"continue_turn\""
      assert html =~ "phx-value-id=\"1\""
      # The interrupted tool spinner settles — paused is inactive.
      refute html =~ "loading-spinner"
    end

    test "renders a search query with its results, linking only safe http(s) urls" do
      html =
        render_turn(
          turn([
            %{activity: %{kind: :search_query, id: "s1", query: "eth gas fees"}},
            %{
              activity: %{
                kind: :search_results,
                id: "s1",
                query: "eth gas fees",
                count: 2,
                results: [
                  %{
                    title: "Gas report",
                    url: "https://example.com/gas",
                    domain: "example.com",
                    snippet: nil
                  },
                  # A non-http scheme must render as plain text, never as a link.
                  %{title: "Sketchy", url: "javascript:alert(1)", domain: "", snippet: nil}
                ]
              }
            }
          ])
        )

      assert html =~ "eth gas fees"
      assert html =~ "https://example.com/gas"
      assert html =~ "Sketchy"
      refute html =~ "javascript:alert(1)"
    end

    test "renders mcp calls with a success or error status per call" do
      html =
        render_turn(
          turn([
            %{activity: %{kind: :mcp_call, id: "c1", tool: "fetch_metric_data", args: %{}}},
            %{activity: %{kind: :mcp_result, id: "c1", tool: "fetch_metric_data", ok: true}},
            %{activity: %{kind: :mcp_call, id: "c2", tool: "show_chart", args: %{}}},
            %{
              activity: %{
                kind: :mcp_result,
                id: "c2",
                tool: "show_chart",
                ok: false,
                summary: "tool exploded"
              }
            }
          ])
        )

      assert html =~ "fetch_metric_data"
      assert html =~ "hero-check-circle"
      assert html =~ "show_chart"
      assert html =~ "hero-x-circle"
      assert html =~ "tool exploded"
    end

    test "an unfinished call spins while running but settles neutrally once the turn ends" do
      # A call with no result: while the turn runs it is genuinely in flight, but
      # on a terminal turn it must NOT keep spinning forever — nor be shown as a
      # success or a failure, because the outcome is simply unknown.
      results = [%{activity: %{kind: :mcp_call, id: "c1", tool: "trending_stories", args: %{}}}]

      running = render_turn(turn(results), running: true, now_ms: @now)
      assert running =~ "loading-spinner"
      refute running =~ "Interrupted"

      # No spinner, no success check anywhere (not on the call row, not on either
      # enclosing group header) and no error cross — the outcome is unknown.
      cancelled = render_turn(turn(results, %{phase: :cancelled, finished_at: @now}))
      assert cancelled =~ "Interrupted"
      refute cancelled =~ "loading-spinner"
      refute cancelled =~ "hero-check-circle"
      refute cancelled =~ "hero-x-circle"
    end

    test "renders subagent findings" do
      html =
        render_turn(
          turn([
            %{
              activity: %{
                kind: :subagent_findings,
                unit: "on-chain",
                summary: "Fees fell 20%",
                findings: [%{"claim" => "Gas is down", "evidence" => "median fee 4 gwei"}],
                gaps: ["No L2 data"]
              }
            }
          ])
        )

      assert html =~ "Fees fell 20%"
      assert html =~ "Gas is down"
      assert html =~ "No L2 data"
    end

    test "renders a live timeline chart with its series payload" do
      html =
        render_turn(
          turn([
            %{
              activity: %{
                kind: :chart,
                id: "ch1",
                slug: "ethereum",
                range: "30d",
                summary: "Price",
                series: [%{"label" => "price_usd", "points" => [%{"t" => 1, "v" => 2}]}]
              }
            }
          ])
        )

      assert html =~ "LightweightChart"
      assert html =~ "price_usd"
    end

    test "renders a skill invocation" do
      html = render_turn(turn([%{activity: %{kind: :skill, name: "crypto-research"}}]))

      assert html =~ "crypto-research"
    end

    test "renders clarification questions instead of a report" do
      turn =
        turn(
          [%{activity: %{kind: :clarification, questions: ["Which timeframe?"]}}],
          %{phase: :awaiting_user}
        )

      assert render_turn(turn) =~ "Which timeframe?"
    end

    test "renders the report markdown as sanitized html" do
      report = "## Findings\n\nETH fees fell.<script>alert(1)</script>"

      html =
        render_turn(turn([], %{report: report, phase: :completed, finished_at: @now + 5_000}))

      assert html =~ "Findings"
      assert html =~ "ETH fees fell."
      refute html =~ "<script>"
    end

    test "renders an in-report chart fence as a server-side svg" do
      report = """
      ## Sources of chatter

      ```chart
      {"type": "pie", "title": "Messages by source", "slices": [{"label": "Twitter", "value": 70}, {"label": "Reddit", "value": 30}]}
      ```
      """

      html = render_turn(turn([], %{report: report, phase: :completed, finished_at: @now}))

      assert html =~ "Messages by source"
      assert html =~ "Twitter"
      assert html =~ "70%"
      assert html =~ "<svg"
      # The fence is consumed, not printed as a code block. (The raw markdown does
      # still appear once, in the copy button's data-copy payload — by design.)
      refute html =~ "<pre"
      refute html =~ "<code"
    end

    test "renders the error of a failed turn" do
      turn = turn([], %{phase: :failed, error: "Agent budget exhausted", finished_at: @now})

      assert render_turn(turn) =~ "Agent budget exhausted"
    end

    test "a finished turn needs no wall clock — it renders with now_ms nil" do
      # This is what keeps completed turns out of the per-second re-render.
      turn =
        turn([%{thinking: %{id: "m1", text: "done"}}], %{
          phase: :completed,
          report: "ok",
          finished_at: @now + 12_000
        })

      html = render_turn(turn, now_ms: nil)

      assert html =~ "12s"
    end

    test "a running turn counts elapsed time from the passed wall clock" do
      turn = turn([%{thinking: %{id: "m1", text: "working"}}], %{phase: :researching})

      html = render_turn(turn, running: true, now_ms: @now + 7_000)

      assert html =~ "7s"
    end
  end
end
