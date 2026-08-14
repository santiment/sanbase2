defmodule Sanbase.DeepResearch.Fixtures do
  @moduledoc """
  Persisted deep research sessions for tests, written through the `Sessions`
  context exactly as the live write path would leave them.
  """

  alias Sanbase.DeepResearch.{Sessions, Turn}

  @started_at 1_754_820_000_000
  @finished_at 1_754_820_090_000

  @doc "A completed one-turn session owned by `user`. Pass `public?: true` to share it."
  def completed_session(user, opts \\ []) do
    session = one_turn_session(user, phase: :completed, report: "## Findings\n\nFees fell.")

    if opts[:public?] do
      {:ok, session} = Sessions.toggle_public(session.id, user.id)
      session
    else
      session
    end
  end

  @doc "A one-turn session owned by `user`, its turn left `:paused` mid-timeline."
  def paused_session(user) do
    one_turn_session(user,
      phase: :paused,
      timeline: [%{kind: :thinking, id: "m1", text: "Scanning on-chain data"}]
    )
  end

  # The two writes the live path makes: the asked turn, then the settled one.
  defp one_turn_session(user, settled_attrs) do
    asked = %Turn{id: 1, question: "ETH drivers?", started_at: @started_at}
    {:ok, %{session: session}} = Sessions.start_session(user.id, "mid", asked)

    settled = struct!(%{asked | finished_at: @finished_at}, settled_attrs)
    {:ok, _} = Sessions.update_turn(session.id, 1, settled)

    session
  end
end
