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

  require Logger

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
    source = Keyword.get(opts, :source, :unknown)
    backend = label(impl)
    candidate_count = length(candidates)
    prompt_bytes = candidates_byte_size(candidates)

    Logger.debug(
      "Reranker start: source=#{source} backend=#{backend} candidates=#{candidate_count} prompt_bytes=#{prompt_bytes}"
    )

    start_mono = System.monotonic_time()
    result = safe_rerank(impl, query, candidates, opts)

    took_ms =
      System.convert_time_unit(System.monotonic_time() - start_mono, :native, :millisecond)

    {outcome, reranked} =
      case result do
        {:ok, list} ->
          {:ok, maybe_take(list, top_n)}

        {:error, reason} ->
          Logger.warning(
            "Reranker fallback: backend=#{backend} source=#{source} reason=#{inspect(reason)}"
          )

          {:fallback, maybe_take(candidates, top_n)}
      end

    Logger.debug(
      "Reranker done:  source=#{source} backend=#{backend} outcome=#{outcome} took_ms=#{took_ms} candidates_in=#{candidate_count} candidates_out=#{length(reranked)}"
    )

    reranked
  end

  defp candidates_byte_size(candidates) do
    Enum.reduce(candidates, 0, fn %{text: t}, acc -> acc + byte_size(t) end)
  end

  @doc """
  The reranker module that will be used when no `:reranker` override is
  passed to `call/3`. Falls back to `Sanbase.Knowledge.Reranker.Noop`
  when unconfigured.
  """
  @spec default_impl() :: module()
  def default_impl() do
    :sanbase
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:default, Sanbase.Knowledge.Reranker.Noop)
  end

  @doc """
  Short, human-readable label for a reranker module — the last segment
  of its module name (e.g. `Sanbase.Knowledge.Reranker.OpenAI` ->
  `"OpenAI"`).
  """
  @spec label(module()) :: String.t()
  def label(mod) when is_atom(mod) do
    mod |> Module.split() |> List.last()
  end

  defp safe_rerank(impl, query, candidates, opts) do
    if is_atom(impl) and Code.ensure_loaded?(impl) and function_exported?(impl, :rerank, 3) do
      try do
        impl.rerank(query, candidates, opts)
      rescue
        e -> {:error, {:reranker_crash, e}}
      end
    else
      {:error, {:invalid_reranker, impl}}
    end
  end

  defp maybe_take(list, nil), do: list
  defp maybe_take(list, n) when is_integer(n) and n >= 0, do: Enum.take(list, n)
  defp maybe_take(list, _invalid), do: list
end
