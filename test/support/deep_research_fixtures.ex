defmodule Sanbase.DeepResearch.Fixtures do
  @moduledoc """
  Persisted deep research sessions for tests, written through the `Sessions`
  context exactly as the live write path would leave them.
  """

  alias Sanbase.DeepResearch.{Sessions, Turn}

  @doc "A completed one-turn session owned by `user`. Pass `public?: true` to share it."
  def completed_session(user, opts \\ []) do
    {:ok, %{session: session}} =
      Sessions.start_session(user.id, "mid", %Turn{
        id: 1,
        question: "ETH drivers?",
        started_at: 1_754_820_000_000
      })

    {:ok, _} =
      Sessions.update_turn(session.id, 1, %Turn{
        id: 1,
        question: "ETH drivers?",
        report: "## Findings\n\nFees fell.",
        phase: :completed,
        started_at: 1_754_820_000_000,
        finished_at: 1_754_820_090_000
      })

    if opts[:public?] do
      {:ok, session} = Sessions.toggle_public(session.id, user.id)
      session
    else
      session
    end
  end
end
