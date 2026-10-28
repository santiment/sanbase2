defmodule SanbaseWeb.Admin.AiBotReviewController do
  @moduledoc """
  JSONL export for the AI bot review admin page. Takes the page's filters, so
  the file holds exactly the rows the page showed, one JSON object per line.
  """

  use SanbaseWeb, :controller

  alias Sanbase.DiscordBot.AiContextReview

  def export(conn, params) do
    filters = AiContextReview.parse_filters(params)

    jsonl =
      filters
      |> AiContextReview.list_for_filters()
      |> AiContextReview.select(filters)
      |> AiContextReview.to_jsonl()

    filename = "ai_bot_review_#{filters.from}_#{filters.to}.jsonl"

    conn
    |> put_resp_content_type("application/x-ndjson")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, jsonl)
  end
end
