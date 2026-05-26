defmodule Sanbase.Knowledge.Reranker.Noop do
  @moduledoc """
  Identity reranker. Returns candidates in input order without consulting
  any external model.

  Used as the baseline in `mix knowledge_eval --no-rerank` and as the
  default in tests so the test suite never calls OpenAI.
  """

  @behaviour Sanbase.Knowledge.Reranker

  @impl true
  def rerank(_query, candidates, _opts), do: {:ok, candidates}
end
