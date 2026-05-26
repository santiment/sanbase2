defmodule Sanbase.Knowledge.Reranker do
  @moduledoc """
  Behavior for retrieval rerankers used by `Sanbase.Knowledge`.

  A reranker takes the user query and a list of candidates already
  produced by the coarse retrieval pass (cosine over pgvector) and
  returns the same candidates re-ordered by relevance.

  Candidates are normalized to the shape below so backends don't need
  to know about source-specific schemas like `FaqEntry`,
  `AcademyArticleChunk`, or insight chunks.
  """

  @type candidate :: %{
          required(:id) => term(),
          required(:text) => String.t(),
          required(:similarity) => float() | nil,
          optional(:source) => :faq | :academy | :insight,
          optional(:metadata) => map()
        }

  @callback rerank(query :: String.t(), candidates :: [candidate()], opts :: keyword()) ::
              {:ok, [candidate()]} | {:error, term()}

  @doc """
  Dispatch to the configured reranker.

  Returns the reranked list (optionally truncated to `:top_n`). On any
  `{:error, _}` reply from the backend, falls back to the input order
  truncated to `:top_n` so the calling query path never fails because
  rerank failed.

  Options:

    * `:reranker` — module implementing the behavior. Defaults to the
      module configured under `:sanbase, Sanbase.Knowledge.Reranker,
      :default`, or `Sanbase.Knowledge.Reranker.Noop` if unset.
    * `:top_n` — truncate the returned list to this many candidates.
    * any other keys are forwarded to the backend's `rerank/3`.
  """
  @spec call(String.t(), [candidate()], keyword()) :: [candidate()]
  def call(query, candidates, opts \\ []) do
    impl = Keyword.get(opts, :reranker, default_impl())
    top_n = Keyword.get(opts, :top_n)

    case impl.rerank(query, candidates, opts) do
      {:ok, reranked} -> maybe_take(reranked, top_n)
      {:error, _reason} -> maybe_take(candidates, top_n)
    end
  end

  defp maybe_take(list, nil), do: list
  defp maybe_take(list, n) when is_integer(n) and n >= 0, do: Enum.take(list, n)

  defp default_impl() do
    :sanbase
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:default, Sanbase.Knowledge.Reranker.Noop)
  end
end
