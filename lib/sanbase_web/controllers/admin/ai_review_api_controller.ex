defmodule SanbaseWeb.Admin.AiReviewApiController do
  @moduledoc """
  JSON API over the AI bot review issues (`Sanbase.DiscordBot.AiReviewIssues`),
  for a poller that runs every few minutes. Auth: `SanbaseWeb.Plug.AiReviewApiAuth`.

    * `GET  /admin_api/ai_review/issues?status=open,recurred&since=<cursor>&limit=100`
      Issues changed after `since`, oldest change first. Pass the returned
      `next_since` as `since` in the next call.
    * `GET  /admin_api/ai_review/issues/:id?turns_limit=20` - one issue with its turns
    * `POST /admin_api/ai_review/issues/:id/resolve` - body `{"note": "..."}`
    * `POST /admin_api/ai_review/issues/:id/reopen`
  """

  use SanbaseWeb, :controller

  alias Sanbase.DiscordBot.{AiContextReview, AiReviewIssue, AiReviewIssues}

  @max_turns 100

  def index(conn, params) do
    with {:ok, since} <- parse_since(params["since"]),
         {:ok, statuses} <- parse_statuses(params["status"]),
         {:ok, limit} <- parse_int(params["limit"], 100) do
      {issues, next_since} = AiReviewIssues.list(since: since, statuses: statuses, limit: limit)

      json(conn, %{
        issues: Enum.map(issues, &issue_json/1),
        next_since: next_since && DateTime.to_iso8601(next_since)
      })
    else
      {:error, message} -> error(conn, 400, message)
    end
  end

  def show(conn, %{"id" => id} = params) do
    with {:ok, id} <- parse_int(id, nil),
         {:ok, turns_limit} <- parse_int(params["turns_limit"], 20),
         {:ok, issue} <- AiReviewIssues.get(id) do
      turns = AiReviewIssues.turns(issue, min(turns_limit, @max_turns))
      json(conn, %{issue: issue_json(issue), turns: Enum.map(turns, &turn_json/1)})
    else
      {:error, :not_found} -> error(conn, 404, "Issue not found")
      {:error, message} -> error(conn, 400, message)
    end
  end

  def resolve(conn, %{"id" => id} = params) do
    note = if is_binary(params["note"]), do: String.slice(params["note"], 0, 5000)

    update(conn, id, fn issue ->
      AiReviewIssues.resolve(issue, conn.assigns.current_user, note)
    end)
  end

  def reopen(conn, %{"id" => id}) do
    update(conn, id, &AiReviewIssues.reopen/1)
  end

  defp update(conn, id, fun) do
    with true <- conn.assigns.ai_review_can_write?,
         {:ok, id} <- parse_int(id, nil),
         {:ok, issue} <- AiReviewIssues.get(id),
         {:ok, issue} <- fun.(issue) do
      json(conn, %{issue: issue_json(issue)})
    else
      false -> error(conn, 403, "An Admin Panel Editor or Owner role is required")
      {:error, :not_found} -> error(conn, 404, "Issue not found")
      {:error, %Ecto.Changeset{}} -> error(conn, 422, "Could not update the issue")
      {:error, message} -> error(conn, 400, message)
    end
  end

  defp issue_json(%AiReviewIssue{} = issue) do
    %{
      id: issue.id,
      signature: issue.signature,
      flag: issue.flag,
      status: issue.status,
      occurrences: issue.occurrences,
      recurrences: issue.recurrences,
      first_seen_at: issue.first_seen_at,
      last_seen_at: issue.last_seen_at,
      resolved_at: issue.resolved_at,
      resolved_by:
        issue.resolved_by && %{id: issue.resolved_by.id, username: issue.resolved_by.username},
      resolution_note: issue.resolution_note,
      updated_at: issue.updated_at,
      latest_turn: issue.last_ai_context && turn_json(issue.last_ai_context)
    }
  end

  defp turn_json(context) do
    %{context: context, flags: AiContextReview.flags_for(context)}
    |> AiContextReview.export_row()
    |> Map.put(
      :langfuse_url,
      context.langfuse_trace_id && AiContextReview.langfuse_trace_url(context.langfuse_trace_id)
    )
  end

  defp parse_since(nil), do: {:ok, nil}

  defp parse_since(since) do
    case DateTime.from_iso8601(since) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _ -> {:error, "`since` must be an ISO 8601 datetime, e.g. a previous `next_since`"}
    end
  end

  defp parse_statuses(nil), do: {:ok, []}

  defp parse_statuses(value) do
    statuses = value |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

    case statuses -- AiReviewIssue.statuses() do
      [] ->
        {:ok, statuses}

      bad ->
        {:error,
         "Unknown status #{Enum.join(bad, ", ")}. Use #{Enum.join(AiReviewIssue.statuses(), ", ")}"}
    end
  end

  defp parse_int(nil, nil), do: {:error, "Missing integer"}
  defp parse_int(nil, default), do: {:ok, default}

  defp parse_int(value, _default) do
    case Integer.parse(to_string(value)) do
      {int, ""} when int > 0 -> {:ok, int}
      _ -> {:error, "Expected a positive integer, got #{inspect(value)}"}
    end
  end

  defp error(conn, status, message) do
    conn
    |> put_status(status)
    |> json(%{error: message})
  end
end
