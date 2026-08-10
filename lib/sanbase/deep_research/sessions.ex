defmodule Sanbase.DeepResearch.Sessions do
  @moduledoc """
  Persistence for deep research conversations: sessions (author, model tier,
  share flag) and their turns, stored as one row per turn.

  All Repo access for the feature lives here. Reads decode rows back into
  `Sanbase.DeepResearch.Turn` structs (via `TurnCodec`), so callers render
  persisted history exactly like a live transcript.

  Authorization: mutations and `get_session_for_user/2` are owner-only;
  `get_public_session/1` only requires `is_public` — "must be logged in" is the
  router's concern. `:forbidden` and `:not_found` are distinct here for tests;
  the UI collapses both so a session id never leaks its existence.
  """

  import Ecto.Query

  alias Sanbase.DeepResearch.Sessions.{Session, SessionTurn, TurnCodec}
  alias Sanbase.DeepResearch.{Timeline, Turn}
  alias Sanbase.Repo

  @title_max_length 80
  @interrupted_error "Interrupted — the research run did not finish (connection lost or the app restarted)."

  @type session_with_turns :: %{session: Session.t(), turns: [Turn.t()]}

  @doc "Create a session owned by `user_id` plus the row for its first turn."
  @spec start_session(integer(), String.t(), Turn.t()) ::
          {:ok, %{session: Session.t(), turn: SessionTurn.t()}} | {:error, Ecto.Changeset.t()}
  def start_session(user_id, model_tier, %Turn{} = turn) do
    Repo.transaction(fn ->
      with {:ok, session} <-
             %Session{}
             |> Session.changeset(%{
               user_id: user_id,
               model_tier: model_tier,
               title: generate_title(turn.question)
             })
             |> Repo.insert(),
           {:ok, row} <- create_turn(session.id, turn, model_tier) do
        %{session: session, turn: row}
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc "Insert the row for a follow-up turn of an existing session."
  @spec create_turn(Ecto.UUID.t(), Turn.t(), String.t() | nil) ::
          {:ok, SessionTurn.t()} | {:error, Ecto.Changeset.t()}
  def create_turn(session_id, %Turn{} = turn, model_tier \\ nil) do
    attrs =
      turn
      |> TurnCodec.turn_to_attrs()
      |> Map.merge(%{session_id: session_id, model_tier: model_tier})

    %SessionTurn{} |> SessionTurn.changeset(attrs) |> Repo.insert()
  end

  @doc "Patch the turn at `position` with the turn's current state (the terminal write)."
  @spec update_turn(Ecto.UUID.t(), integer(), Turn.t()) ::
          {:ok, SessionTurn.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def update_turn(session_id, position, %Turn{} = turn) do
    case Repo.get_by(SessionTurn, session_id: session_id, position: position) do
      nil -> {:error, :not_found}
      row -> row |> SessionTurn.changeset(TurnCodec.turn_to_attrs(turn)) |> Repo.update()
    end
  end

  @doc "Record the LangGraph thread id once it is known (first turn only)."
  @spec set_thread_id(Ecto.UUID.t(), String.t()) :: :ok
  def set_thread_id(session_id, thread_id) when is_binary(thread_id) do
    from(s in Session, where: s.id == ^session_id and is_nil(s.thread_id))
    |> Repo.update_all(set: [thread_id: thread_id])

    :ok
  end

  @doc "Bump `updated_at` so the session sorts to the top of the sidebar."
  @spec touch_session(Ecto.UUID.t()) :: :ok
  def touch_session(session_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(s in Session, where: s.id == ^session_id)
    |> Repo.update_all(set: [updated_at: now])

    :ok
  end

  @doc "The user's sessions, most recently updated first. Turns are not loaded."
  @spec list_user_sessions(integer()) :: [Session.t()]
  def list_user_sessions(user_id) do
    from(s in Session, where: s.user_id == ^user_id, order_by: [desc: s.updated_at])
    |> Repo.all()
  end

  @doc "An owned session with its decoded turns; `:forbidden` for someone else's."
  @spec get_session_for_user(Ecto.UUID.t(), integer()) ::
          {:ok, session_with_turns()} | {:error, :not_found | :forbidden}
  def get_session_for_user(session_id, user_id) do
    with {:ok, session} <- fetch_session(session_id) do
      if session.user_id == user_id,
        do: {:ok, load_turns(session)},
        else: {:error, :forbidden}
    end
  end

  @doc "A shared session with its decoded turns. Caller identity is not checked."
  @spec get_public_session(Ecto.UUID.t()) ::
          {:ok, session_with_turns()} | {:error, :not_found}
  def get_public_session(session_id) do
    with {:ok, session} <- fetch_session(session_id) do
      if session.is_public,
        do: {:ok, load_turns(session)},
        else: {:error, :not_found}
    end
  end

  @doc "Flip sharing on or off. Owner only."
  @spec toggle_public(Ecto.UUID.t(), integer()) ::
          {:ok, Session.t()} | {:error, :not_found | :forbidden | Ecto.Changeset.t()}
  def toggle_public(session_id, user_id) do
    with {:ok, session} <- fetch_owned_session(session_id, user_id) do
      session |> Session.changeset(%{is_public: not session.is_public}) |> Repo.update()
    end
  end

  @doc "Delete a session and (via FK) its turns. Owner only."
  @spec delete_session(Ecto.UUID.t(), integer()) ::
          {:ok, Session.t()} | {:error, :not_found | :forbidden}
  def delete_session(session_id, user_id) do
    with {:ok, session} <- fetch_owned_session(session_id, user_id) do
      Repo.delete(session)
    end
  end

  @doc "First-question title for the sidebar, truncated to #{@title_max_length} chars."
  @spec generate_title(String.t()) :: String.t()
  def generate_title(question) do
    trimmed = String.trim(question)

    if String.length(trimmed) > @title_max_length,
      do: String.slice(trimmed, 0, @title_max_length) <> "...",
      else: trimmed
  end

  # -- internal ------------------------------------------------------------------

  defp fetch_session(session_id) do
    with {:ok, uuid} <- Ecto.UUID.cast(session_id),
         %Session{} = session <- Repo.get(Session, uuid) do
      {:ok, session}
    else
      _ -> {:error, :not_found}
    end
  end

  defp fetch_owned_session(session_id, user_id) do
    with {:ok, session} <- fetch_session(session_id) do
      if session.user_id == user_id, do: {:ok, session}, else: {:error, :forbidden}
    end
  end

  defp load_turns(session) do
    rows =
      from(t in SessionTurn, where: t.session_id == ^session.id, order_by: [asc: t.position])
      |> Repo.all()
      |> Enum.map(&reconcile_interrupted_turn/1)

    %{session: session, turns: Enum.map(rows, &TurnCodec.from_row/1)}
  end

  # A row still unsettled at read time means the LiveView died mid-run (the
  # settling write never happened). Coerce it to a stable failed state and
  # PERSIST the coercion, so every later viewer sees the same thing. A second
  # tab peeking at a session still streaming in another tab would mark it
  # failed early — accepted: the real settling write self-heals the row.
  defp reconcile_interrupted_turn(row) do
    if Timeline.settled_phase?(row.phase) do
      row
    else
      attrs = %{
        phase: :failed,
        error: row.error || @interrupted_error,
        finished_at: row.finished_at || DateTime.utc_now()
      }

      case row |> SessionTurn.changeset(attrs) |> Repo.update() do
        {:ok, updated} -> updated
        {:error, _} -> row
      end
    end
  end
end
