defmodule Sanbase.DeepResearch.SessionsTest do
  use Sanbase.DataCase, async: true

  import Sanbase.Factory
  import Ecto.Query

  alias Sanbase.DeepResearch.Sessions
  alias Sanbase.DeepResearch.Sessions.{Session, SessionTurn}
  alias Sanbase.DeepResearch.Turn
  alias Sanbase.Repo

  defp new_turn(id \\ 1, question \\ "What is driving ETH?") do
    %Turn{id: id, question: question, started_at: 1_754_820_000_000}
  end

  defp finished_turn(id \\ 1) do
    %Turn{
      id: id,
      question: "What is driving ETH?",
      report: "## Findings\n\nFees fell.",
      phase: :completed,
      started_at: 1_754_820_000_000,
      finished_at: 1_754_820_090_000,
      timeline: [%{kind: :thinking, id: "m1", text: "Scanning"}],
      sources: [%{url: "https://example.com", title: "Src", domain: "example.com"}]
    }
  end

  describe "start_session/3" do
    test "creates a session with its first turn row" do
      user = insert(:user)

      assert {:ok, %{session: session, turn: row}} =
               Sessions.start_session(user.id, "mid", new_turn())

      assert session.user_id == user.id
      assert session.model_tier == "mid"
      assert session.title == "What is driving ETH?"
      assert session.is_public == false

      assert row.session_id == session.id
      assert row.position == 1
      assert row.phase == :queued
      assert row.model_tier == "mid"
    end

    test "truncates a long question into the title" do
      user = insert(:user)
      question = String.duplicate("a", 100)

      assert {:ok, %{session: session}} =
               Sessions.start_session(user.id, "mid", new_turn(1, question))

      assert session.title == String.duplicate("a", 80) <> "..."
    end

    test "fails for a missing user without leaving a session behind" do
      assert {:error, _changeset} = Sessions.start_session(999_999_999, "mid", new_turn())
      assert Repo.aggregate(Session, :count) == 0
    end
  end

  describe "create_turn/3 and update_turn/3" do
    setup do
      user = insert(:user)
      {:ok, %{session: session}} = Sessions.start_session(user.id, "mid", new_turn())
      %{user: user, session: session}
    end

    test "create_turn appends a follow-up row", %{session: session} do
      assert {:ok, row} = Sessions.create_turn(session.id, new_turn(2, "And SOL?"), "high")

      assert row.position == 2
      assert row.question == "And SOL?"
      assert row.model_tier == "high"
    end

    test "a duplicate position is rejected", %{session: session} do
      assert {:error, changeset} = Sessions.create_turn(session.id, new_turn(1, "dup"))
      assert %{session_id: _} = errors_on(changeset)
    end

    test "update_turn patches the row to the turn's terminal state", %{session: session} do
      assert {:ok, row} = Sessions.update_turn(session.id, 1, finished_turn())

      assert row.phase == :completed
      assert row.report =~ "Fees fell."
      assert row.finished_at
      assert [%{"kind" => "thinking"}] = Repo.reload!(row).timeline
    end

    test "update_turn on an unknown position returns not_found", %{session: session} do
      assert {:error, :not_found} = Sessions.update_turn(session.id, 42, finished_turn(42))
    end
  end

  describe "set_thread_id/2 and touch_session/1" do
    test "set_thread_id records the thread once and never overwrites" do
      user = insert(:user)
      {:ok, %{session: session}} = Sessions.start_session(user.id, "mid", new_turn())

      :ok = Sessions.set_thread_id(session.id, "thread-1")
      :ok = Sessions.set_thread_id(session.id, "thread-2")

      assert Repo.reload!(session).thread_id == "thread-1"
    end

    test "touch_session bumps updated_at" do
      user = insert(:user)
      {:ok, %{session: session}} = Sessions.start_session(user.id, "mid", new_turn())

      past = DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.truncate(:second)

      from(s in Session, where: s.id == ^session.id)
      |> Repo.update_all(set: [updated_at: past])

      :ok = Sessions.touch_session(session.id)

      assert DateTime.compare(Repo.reload!(session).updated_at, past) == :gt
    end
  end

  describe "list_user_sessions/1" do
    test "returns only the user's sessions, most recently updated first" do
      user = insert(:user)
      other = insert(:user)

      {:ok, %{session: s1}} = Sessions.start_session(user.id, "mid", new_turn(1, "first"))
      {:ok, %{session: s2}} = Sessions.start_session(user.id, "mid", new_turn(1, "second"))
      {:ok, _} = Sessions.start_session(other.id, "mid", new_turn(1, "not mine"))

      # Deterministic ordering regardless of insert timing granularity.
      set_updated_at(s1, -100)
      set_updated_at(s2, -200)

      assert [%{id: first_id}, %{id: second_id}] = Sessions.list_user_sessions(user.id)
      assert first_id == s1.id
      assert second_id == s2.id
    end
  end

  describe "get_session_for_user/2 and get_public_session/1" do
    setup do
      user = insert(:user)
      {:ok, %{session: session}} = Sessions.start_session(user.id, "mid", new_turn())
      {:ok, _} = Sessions.update_turn(session.id, 1, finished_turn())
      %{user: user, session: session}
    end

    test "the owner gets the session with decoded turns", %{user: user, session: session} do
      assert {:ok, %{session: loaded, turns: [turn]}} =
               Sessions.get_session_for_user(session.id, user.id)

      assert loaded.id == session.id
      assert %Turn{} = turn
      assert turn.id == 1
      assert turn.report =~ "Fees fell."
      assert turn.phase == :completed
      assert [%{kind: :thinking, text: "Scanning"}] = turn.timeline
    end

    test "someone else's session is forbidden", %{session: session} do
      other = insert(:user)

      assert {:error, :forbidden} = Sessions.get_session_for_user(session.id, other.id)
    end

    test "an unknown or malformed id is not_found", %{user: user} do
      assert {:error, :not_found} = Sessions.get_session_for_user(Ecto.UUID.generate(), user.id)
      assert {:error, :not_found} = Sessions.get_session_for_user("not-a-uuid", user.id)
    end

    test "get_public_session requires the share flag", %{user: user, session: session} do
      assert {:error, :not_found} = Sessions.get_public_session(session.id)

      {:ok, _} = Sessions.toggle_public(session.id, user.id)

      assert {:ok, %{turns: [%Turn{report: report}]}} = Sessions.get_public_session(session.id)
      assert report =~ "Fees fell."
    end
  end

  describe "interrupted turn reconciliation" do
    test "a non-terminal turn loads as paused (resumable), without touching the row" do
      user = insert(:user)
      {:ok, %{session: session}} = Sessions.start_session(user.id, "mid", new_turn())

      # The row is stuck in :queued — the runner died before the settling write.
      assert {:ok, %{turns: [turn]}} = Sessions.get_session_for_user(session.id, user.id)

      assert turn.phase == :paused
      assert turn.error == nil
      assert turn.finished_at

      # Not persisted: the row may belong to a runner on another node.
      row = Repo.one!(from(t in SessionTurn, where: t.session_id == ^session.id))
      assert row.phase == :queued
      assert row.finished_at == nil
    end

    test "a public read shows an interrupted turn as paused, without touching the row" do
      user = insert(:user)
      {:ok, %{session: session}} = Sessions.start_session(user.id, "mid", new_turn())
      {:ok, _} = Sessions.toggle_public(session.id, user.id)

      assert {:ok, %{turns: [turn]}} = Sessions.get_public_session(session.id)

      assert turn.phase == :paused
      assert turn.finished_at

      row = Repo.one!(from(t in SessionTurn, where: t.session_id == ^session.id))
      assert row.phase == :queued
      assert row.finished_at == nil
    end

    test "a terminal turn is left untouched" do
      user = insert(:user)
      {:ok, %{session: session}} = Sessions.start_session(user.id, "mid", new_turn())
      {:ok, _} = Sessions.update_turn(session.id, 1, finished_turn())

      assert {:ok, %{turns: [turn]}} = Sessions.get_session_for_user(session.id, user.id)

      assert turn.phase == :completed
      assert turn.error == nil
    end

    test "an awaiting_user (clarification) turn is settled, not interrupted" do
      user = insert(:user)
      {:ok, %{session: session}} = Sessions.start_session(user.id, "mid", new_turn())

      clarification_turn = %Turn{
        id: 1,
        question: "What is driving ETH?",
        clarification: ["Which time range?"],
        phase: :awaiting_user,
        started_at: 1_754_820_000_000,
        finished_at: 1_754_820_005_000
      }

      {:ok, _} = Sessions.update_turn(session.id, 1, clarification_turn)

      assert {:ok, %{turns: [turn]}} = Sessions.get_session_for_user(session.id, user.id)

      assert turn.phase == :awaiting_user
      assert turn.error == nil
      assert turn.clarification == ["Which time range?"]
    end
  end

  describe "toggle_public/2 and delete_session/2" do
    setup do
      user = insert(:user)
      {:ok, %{session: session}} = Sessions.start_session(user.id, "mid", new_turn())
      %{user: user, session: session}
    end

    test "the owner can toggle sharing", %{user: user, session: session} do
      assert {:ok, %Session{is_public: true}} = Sessions.toggle_public(session.id, user.id)
      assert {:ok, %Session{is_public: false}} = Sessions.toggle_public(session.id, user.id)
    end

    test "a non-owner cannot toggle sharing or delete", %{session: session} do
      other = insert(:user)

      assert {:error, :forbidden} = Sessions.toggle_public(session.id, other.id)
      assert {:error, :forbidden} = Sessions.delete_session(session.id, other.id)
    end

    test "delete removes the session and its turns", %{user: user, session: session} do
      assert {:ok, _} = Sessions.delete_session(session.id, user.id)

      assert Repo.get(Session, session.id) == nil
      assert Repo.aggregate(SessionTurn, :count) == 0
    end
  end

  defp set_updated_at(session, seconds_ago_negative) do
    ts =
      DateTime.utc_now()
      |> DateTime.add(seconds_ago_negative)
      |> DateTime.truncate(:second)

    from(s in Session, where: s.id == ^session.id)
    |> Repo.update_all(set: [updated_at: ts])
  end
end
