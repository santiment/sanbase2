defmodule Sanbase.MCP.SearchDocsTool do
  @moduledoc """
  Search across Academy and FAQ and return a combined list of entries
  with fields: source, title, chunk, score.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  @max_results 10
  @max_chunk_length 2000

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

  defp truncate_chunk(%{chunk: chunk} = result) when is_binary(chunk) do
    if String.length(chunk) <= @max_chunk_length do
      result
    else
      %{result | chunk: String.slice(chunk, 0, @max_chunk_length) <> "... [truncated]"}
    end
  end

  defp truncate_chunk(result), do: result

  defp do_execute(params, frame) do
    question = params[:question] || ""

    case Sanbase.AI.AcademyAIService.search_docs(question) do
      {:ok, results} when is_list(results) ->
        limited_results =
          results
          |> Enum.take(@max_results)
          |> Enum.map(&truncate_chunk/1)

        {:reply, Response.json(Response.tool(), limited_results), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), reason), frame}
    end
  end
end
