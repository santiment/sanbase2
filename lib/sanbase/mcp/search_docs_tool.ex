defmodule Sanbase.MCP.SearchDocsTool do
  @moduledoc """
  Search across Academy and FAQ and return a combined list of entries
  with fields: source, title, chunk, score.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  schema do
    field(:question, :string,
      required: true,
      description: "The user question to search for"
    )
  end

  @impl true
  def execute(params, frame) do
    do_execute(params, frame)
  end

  defp do_execute(params, frame) do
    question = params[:question] || ""

    case Sanbase.AI.AcademyAIService.search_docs(question) do
      {:ok, results} when is_list(results) ->
        # Return same info as the function: list of maps with source, title, chunk, score
        {:reply, Response.json(Response.tool(), results), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), reason), frame}
    end
  end
end
