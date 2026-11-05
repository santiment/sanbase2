defmodule Sanbase.DiscordBot.AiReviewIssues do
  @moduledoc """
  Groups the problems found in AI bot turns into issues that can be polled,
  marked resolved, and noticed again when they come back.

  Each review flag of a turn (see `Sanbase.DiscordBot.AiContextReview`) maps to
  a signature:

    * `tool_issue:<tool>:<kind>` - one per entry in `tool_issues`
    * `error:<error_message>` / `degraded:<error_message>`
    * `delivery_failed:<delivery_error>`
    * `language_mismatch`, `slow`
    * `downvoted:<turn id>` - a vote has nothing to group by, so each
      downvoted turn is its own issue

  Messages are normalized (digits replaced, cut to 120 characters) so ids
  and counts in them do not split one problem into many issues.

  `record/1` is called whenever a turn is written or updated (created, delivery
  recorded, vote added), so an issue appears as soon as its turn does. It is
  idempotent: a turn is counted once per issue. A turn newer than the
  resolution of a resolved issue turns it into `recurred`.
  """

  import Ecto.Query

  require Logger

  alias Sanbase.DiscordBot.{AiContext, AiContextReview, AiReviewIssue}
  alias Sanbase.Repo

  @message_length 120
  @default_limit 100
  @max_limit 500

  @doc """
  Records the issues of a turn. Never raises: a failure here must not break
  the bot, so it is logged and `:error` is returned.
  """
  def record(%AiContext{} = context) do
    context
    |> signatures()
    |> Enum.each(fn {signature, flag} -> record_issue(context, signature, flag) end)

    :ok
  rescue
    error ->
      Logger.error(
        "Could not record AI review issues for ai_context #{context.id}: " <>
          Exception.message(error)
      )

      :error
  end

  @doc "`{signature, flag}` pairs for the problems of a turn."
  def signatures(%AiContext{} = context) do
    context
    |> AiContextReview.flags_for()
    |> Enum.flat_map(fn
      "tool_issue" ->
        Enum.map(context.tool_issues || [], &{"tool_issue:#{&1}", "tool_issue"})

      "error" ->
        [{"error:" <> normalize(context.error_message), "error"}]

      "degraded" ->
        [{"degraded:" <> normalize(context.error_message), "degraded"}]

      "delivery_failed" ->
        [{"delivery_failed:" <> normalize(context.delivery_error), "delivery_failed"}]

      "downvoted" ->
        [{"downvoted:#{context.id}", "downvoted"}]

      flag ->
        [{flag, flag}]
    end)
    |> Enum.uniq()
  end

  defp normalize(nil), do: "unknown"

  defp normalize(message) do
    message
    |> String.replace(~r/\d+/u, "N")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> String.slice(0, @message_length)
  end

  defp record_issue(context, signature, flag) do
    seen_at = context.inserted_at
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      Repo.insert_all(
        AiReviewIssue,
        [
          %{
            signature: signature,
            flag: flag,
            status: "open",
            first_seen_at: seen_at,
            last_seen_at: seen_at,
            last_ai_context_id: context.id,
            inserted_at: now,
            updated_at: now
          }
        ],
        on_conflict: :nothing,
        conflict_target: :signature
      )

      issue =
        Repo.one!(from(i in AiReviewIssue, where: i.signature == ^signature, lock: "FOR UPDATE"))

      {linked, _} =
        Repo.insert_all(
          "ai_review_issue_turns",
          [
            %{
              issue_id: issue.id,
              ai_context_id: context.id,
              inserted_at: DateTime.truncate(now, :second)
            }
          ],
          on_conflict: :nothing,
          conflict_target: [:issue_id, :ai_context_id]
        )

      if linked == 1, do: count_turn(issue, context, now)
    end)
  end

  # Called once per (issue, turn): bumps the counters, keeps the newest turn,
  # and reopens a resolved issue when the turn came after the resolution.
  defp count_turn(issue, context, now) do
    seen_at = context.inserted_at
    newer? = NaiveDateTime.compare(seen_at, issue.last_seen_at) != :lt

    recurred? =
      issue.status == "resolved" and not is_nil(issue.resolved_at) and
        DateTime.compare(DateTime.from_naive!(seen_at, "Etc/UTC"), issue.resolved_at) == :gt

    changes =
      [
        occurrences: issue.occurrences + 1,
        first_seen_at: Enum.min([issue.first_seen_at, seen_at], NaiveDateTime),
        updated_at: now
      ] ++
        if(newer?, do: [last_seen_at: seen_at, last_ai_context_id: context.id], else: []) ++
        if(recurred?, do: [status: "recurred", recurrences: issue.recurrences + 1], else: [])

    from(i in AiReviewIssue, where: i.id == ^issue.id)
    |> Repo.update_all(set: changes)
  end

  @doc """
  Issues changed after `since` (a cursor from a previous call), oldest change
  first. Returns `{issues, next_since}`; pass `next_since` back to get only the
  issues changed after this page.

  Options:
    * `:since` - `DateTime`, exclusive
    * `:statuses` - list of statuses, default all
    * `:limit` - default #{@default_limit}, at most #{@max_limit}
  """
  def list(opts \\ []) do
    limit = opts |> Keyword.get(:limit, @default_limit) |> min(@max_limit) |> max(1)

    issues =
      from(i in AiReviewIssue,
        order_by: [asc: i.updated_at, asc: i.id],
        limit: ^limit,
        preload: [:last_ai_context, :resolved_by]
      )
      |> maybe_since(opts[:since])
      |> maybe_statuses(opts[:statuses])
      |> Repo.all()

    next_since =
      case List.last(issues) do
        nil -> opts[:since]
        issue -> issue.updated_at
      end

    {issues, next_since}
  end

  defp maybe_since(query, nil), do: query
  defp maybe_since(query, %DateTime{} = since), do: where(query, [i], i.updated_at > ^since)

  defp maybe_statuses(query, statuses) when is_list(statuses) and statuses != [],
    do: where(query, [i], i.status in ^statuses)

  defp maybe_statuses(query, _statuses), do: query

  @doc "Read access: any Admin Panel role."
  def can_read?(role_ids), do: Enum.any?(role_ids, &(&1 in read_role_ids()))

  @doc "Resolve and reopen: an Admin Panel Editor or Owner."
  def can_resolve?(role_ids), do: Enum.any?(role_ids, &(&1 in resolve_role_ids()))

  defp read_role_ids(),
    do: [Sanbase.Accounts.Role.admin_panel_viewer_role_id() | resolve_role_ids()]

  defp resolve_role_ids(),
    do: [
      Sanbase.Accounts.Role.admin_panel_editor_role_id(),
      Sanbase.Accounts.Role.admin_panel_owner_role_id()
    ]

  @doc """
  Issues that still need work (open or recurred), most recently seen first,
  for the review page. With `include_resolved: true`, resolved ones too.
  """
  def list_for_review(opts \\ []) do
    statuses =
      if opts[:include_resolved], do: AiReviewIssue.statuses(), else: ["open", "recurred"]

    from(i in AiReviewIssue,
      where: i.status in ^statuses,
      order_by: [desc: i.last_seen_at, desc: i.id],
      limit: ^Keyword.get(opts, :limit, 100),
      preload: [:last_ai_context, :resolved_by]
    )
    |> Repo.all()
  end

  @doc "The issues of each turn: `%{ai_context_id => [issue]}`."
  def issues_by_turn([]), do: %{}

  def issues_by_turn(context_ids) do
    from(i in AiReviewIssue,
      join: t in "ai_review_issue_turns",
      on: t.issue_id == i.id,
      where: t.ai_context_id in ^context_ids,
      order_by: [asc: i.id],
      select: {t.ai_context_id, i}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  def get(id) do
    case Repo.get(AiReviewIssue, id) do
      nil -> {:error, :not_found}
      issue -> {:ok, Repo.preload(issue, [:last_ai_context, :resolved_by])}
    end
  end

  @doc "The turns of an issue, newest first."
  def turns(%AiReviewIssue{id: issue_id}, limit \\ 20) do
    from(c in AiContext,
      join: t in "ai_review_issue_turns",
      on: t.ai_context_id == c.id,
      where: t.issue_id == ^issue_id,
      order_by: [desc: c.inserted_at, desc: c.id],
      limit: ^limit
    )
    |> Repo.all()
  end

  def resolve(%AiReviewIssue{} = issue, user, note) do
    issue
    |> Ecto.Changeset.change(
      status: "resolved",
      resolved_at: DateTime.utc_now() |> DateTime.truncate(:second),
      resolved_by_id: user.id,
      resolution_note: note
    )
    |> Repo.update()
    |> preload_result()
  end

  @doc "Back to open. The last resolution note is kept for reference."
  def reopen(%AiReviewIssue{} = issue) do
    issue
    |> Ecto.Changeset.change(status: "open")
    |> Repo.update()
    |> preload_result()
  end

  defp preload_result({:ok, issue}),
    do: {:ok, Repo.preload(issue, [:last_ai_context, :resolved_by], force: true)}

  defp preload_result(error), do: error

  @doc """
  Records the issues of the turns in `[from, to)`, e.g. once after deploy for
  the turns written before issues were recorded. Safe to run again.
  """
  def backfill(%NaiveDateTime{} = from, %NaiveDateTime{} = to) do
    from(c in AiContext,
      where: c.inserted_at >= ^from and c.inserted_at < ^to,
      order_by: [asc: c.inserted_at, asc: c.id]
    )
    |> Repo.all()
    |> Enum.each(&record/1)
  end
end
