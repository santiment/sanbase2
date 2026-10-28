defmodule SanbaseWeb.Admin.AiBotReviewController do
  @moduledoc """
  JSONL export for the AI bot review admin page. Takes the page's filters, so
  the file holds exactly the rows the page showed, one JSON object per line.
  """

  use SanbaseWeb, :controller

  alias Sanbase.DiscordBot.AiContextReview
  alias Sanbase.Repo

  def export(conn, params) do
    filters = AiContextReview.parse_filters(params)
    filename = "ai_bot_review_#{filters.from}_#{filters.to}.jsonl"

    conn =
      conn
      |> put_resp_content_type("application/x-ndjson")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
      |> send_chunked(200)

    # The whole range, however long, streamed in batches instead of loaded at once.
    {:ok, conn} =
      Repo.transaction(
        fn ->
          filters
          |> AiContextReview.stream_for_filters()
          |> Stream.map(&AiContextReview.to_jsonl_line/1)
          |> Stream.chunk_every(100)
          |> Enum.reduce_while(conn, fn lines, conn ->
            case chunk(conn, lines) do
              {:ok, conn} -> {:cont, conn}
              {:error, _closed} -> {:halt, conn}
            end
          end)
        end,
        timeout: :timer.minutes(5)
      )

    conn
  end
end
