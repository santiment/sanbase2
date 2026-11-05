defmodule Sanbase.DiscordBot.AiContextReviewDigest do
  @moduledoc """
  Daily email with the AI bot turns (Discord and Telegram) flagged for review in
  the last 24 hours: counts per flag, the flagged turns with their Langfuse
  links, and a link to the review page.

  It is sent at 09:00 Europe/Berlin (CET, CEST in summer). The scheduler starts
  `maybe_send/0` at 07:00 and 08:00 UTC and only the run that falls at 9
  o'clock Berlin time sends, so the hour stays right across daylight saving.
  Only prod sends.
  """

  require Logger

  alias Sanbase.DiscordBot.AiContextReview

  # Kept apart so the address does not appear as one string in the code.
  @recipient_name "tsvetozar.p"
  @recipient_domain "santiment.net"

  @timezone "Europe/Berlin"
  @send_hour 9
  @max_listed 30
  @question_length 160

  def recipient(), do: @recipient_name <> "@" <> @recipient_domain

  @doc "Sends the digest when it is 9 o'clock in Berlin and this is prod."
  def maybe_send() do
    if prod?() and Timex.now(@timezone).hour == @send_hour do
      send_digest()
    else
      :skipped
    end
  end

  def send_digest(now \\ DateTime.utc_now()) do
    to = now |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)
    from = NaiveDateTime.add(to, -24 * 3600, :second)
    rows = AiContextReview.list(from, to)
    {subject, body} = build(rows, from, to)

    case Sanbase.SimpleMailer.send_email(recipient(), subject, body) do
      {:ok, _} = ok ->
        ok

      error ->
        Logger.error("AI bot review digest was not sent: #{inspect(error)}")
        error
    end
  end

  @doc """
  The subject and the plain-text body for the turns in `rows`, which cover
  `[from, to)` (UTC).
  """
  def build(rows, from, to) do
    flagged = Enum.filter(rows, &(&1.flags != []))
    labels = AiContextReview.flag_labels()

    subject =
      "AI bot review #{NaiveDateTime.to_date(to)}: " <>
        "#{length(flagged)} flagged of #{length(rows)} turns"

    counts =
      rows
      |> AiContextReview.flag_counts()
      |> then(fn counts -> Enum.map(AiContextReview.flags(), &{&1, counts[&1]}) end)
      |> Enum.map_join("\n", fn {flag, count} -> "#{labels[flag]}: #{count}" end)

    body =
      [
        "AI bot turns from #{format_time(from)} to #{format_time(to)} UTC: " <>
          "#{length(rows)} turns, #{length(flagged)} flagged.",
        counts,
        flagged_section(flagged, labels),
        "Review page: #{review_url(from, to)}"
      ]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n")

    {subject, body <> "\n"}
  end

  defp flagged_section([], _labels), do: ""

  defp flagged_section(flagged, labels) do
    listed = Enum.take(flagged, @max_listed)

    turns =
      Enum.map_join(listed, "\n\n", fn %{context: c, flags: flags} ->
        flag_names = Enum.map_join(flags, ", ", &labels[&1])

        [
          "#{format_time(c.inserted_at)} #{AiContextReview.platform(c)} #{c.discord_user} [#{flag_names}]",
          "  " <> short_question(c.question),
          c.langfuse_trace_id &&
            "  Langfuse: " <> AiContextReview.langfuse_trace_url(c.langfuse_trace_id)
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n")
      end)

    more =
      case length(flagged) - length(listed) do
        0 -> ""
        n -> "\n\n...and #{n} more on the review page."
      end

    "Flagged turns, newest first:\n\n" <> turns <> more
  end

  defp short_question(nil), do: ""

  defp short_question(question) do
    question = question |> String.replace(~r/\s+/u, " ") |> String.trim()

    if String.length(question) > @question_length,
      do: String.slice(question, 0, @question_length) <> "...",
      else: question
  end

  defp format_time(%NaiveDateTime{} = datetime),
    do: datetime |> NaiveDateTime.truncate(:second) |> Calendar.strftime("%Y-%m-%d %H:%M")

  defp review_url(from, to) do
    query =
      URI.encode_query(
        from: NaiveDateTime.to_date(from),
        to: NaiveDateTime.to_date(to),
        flagged_only: true
      )

    SanbaseWeb.Endpoint.admin_url() <> "/admin/ai_bot_review?" <> query
  end

  defp prod?(), do: Sanbase.Utils.Config.module_get(Sanbase, :deployment_env) == "prod"
end
