defmodule Sanbase.Knowledge.AcademyQuestions do
  @moduledoc """
  Autocomplete question suggestions for the Academy search box
  (`academyAutocompleteQuestions`).

  Each Academy article stores a few questions it answers
  (`academy_articles.suggested_questions`), written once by an LLM from the
  article's indexed chunks. Generation is manual, never part of the reindex,
  so the daily job makes no LLM calls. Run it from a remote shell after new
  content lands:

      alias Sanbase.Knowledge.AcademyQuestions
      AcademyQuestions.generate()              # articles without questions (new content)
      AcademyQuestions.generate(stale: true)   # also articles changed since their questions were made
      AcademyQuestions.generate(force: true)   # all articles
      AcademyQuestions.stats()

  The reindex carries the stored questions over, including for changed or
  force-reindexed articles; `stale: true` picks up the ones whose content
  changed since.

  `suggest/2` matches the typed text against an in-memory index of all
  questions, their article titles and section headings. No API call is made,
  so a lookup takes well under a millisecond. The index is rebuilt on the
  first lookup after `@index_ttl_ms`, so other pods pick up new questions
  within that time.
  """

  import Ecto.Query

  require Logger

  alias Sanbase.Knowledge.{AcademyArticle, AcademyArticleChunk}
  alias Sanbase.Repo

  @model "gpt-5.4-mini"
  @openai_url "https://api.openai.com/v1/chat/completions"
  @questions_per_article 5
  @max_question_chars 160
  @max_article_chars 8_000
  @default_concurrency 4

  @default_limit 5
  @max_per_article 2
  @index_ttl_ms :timer.minutes(10)
  @index_key {__MODULE__, :index}
  @index_lock {__MODULE__, :index_refresh}
  @fuzzy_threshold 0.9

  @stopwords ~w(a an the is are was were be do does did i my me we our you your it its
                of in on at to for from by with and or how what when why where which who
                can could should would will get use using there this that these those)

  @type suggestion :: %{title: String.t(), question: String.t(), url: String.t()}

  # Suggestions ----------------------------------------------------------

  @doc """
  Up to `limit` (default #{@default_limit}) questions matching `query`, at most
  #{@max_per_article} per article.

  Every meaningful word of the query must match a word of the question, its
  article title or one of the article's section headings. The last word may be
  a prefix of a word ("mcp conn" matches "MCP connector"), and words of 4+
  letters also match close misspellings ("exchnage"). When nothing matches all
  words of a multi-word query, questions matching all but one are returned.
  """
  @spec suggest(String.t(), keyword()) :: [suggestion()]
  def suggest(query, opts \\ []) when is_binary(query) do
    limit = Keyword.get(opts, :limit, @default_limit)
    index = Keyword.get_lazy(opts, :index, &index/0)

    case query_tokens(query) do
      [] ->
        []

      tokens ->
        token_kinds =
          Enum.map(Enum.with_index(tokens), &token_kinds(&1, tokens, index.vocabulary))

        index.articles
        |> Enum.flat_map(&score_article(&1, tokens, token_kinds))
        |> best_matching(length(tokens))
        |> Enum.sort_by(fn {_, score, entry} -> {-score, String.length(entry.question)} end)
        |> cap_per_article()
        |> Enum.take(limit)
        |> Enum.map(fn {_, _, entry} ->
          %{title: entry.title, question: entry.question, url: entry.url}
        end)
    end
  end

  # Questions matching every token; when there are none, those matching all but one.
  defp best_matching(scored, n) do
    case Enum.filter(scored, fn {matched, _, _} -> matched == n end) do
      [] when n > 1 -> Enum.filter(scored, fn {matched, _, _} -> matched == n - 1 end)
      full -> full
    end
  end

  @doc "Rebuild the in-memory suggestion index on this node."
  @spec refresh_index() :: :ok
  def refresh_index() do
    :persistent_term.put(@index_key, {now_ms(), build_index()})
    :ok
  end

  # An expired index is rebuilt by one caller, holding a node-local lock, while
  # concurrent callers keep using the expired one. Without an index at all,
  # callers wait for that single rebuild.
  defp index() do
    case :persistent_term.get(@index_key, nil) do
      {loaded_at, index} ->
        if fresh?(loaded_at), do: index, else: rebuild_index(0) || index

      nil ->
        rebuild_index(:infinity)
    end
  end

  # Returns the index, or nil when another process holds the lock and `retries` is 0.
  defp rebuild_index(retries) do
    :global.trans(
      {@index_lock, self()},
      fn ->
        # Another process may have rebuilt it while this one waited for the lock.
        case :persistent_term.get(@index_key, nil) do
          {loaded_at, index} when is_integer(loaded_at) ->
            if fresh?(loaded_at), do: index, else: do_rebuild_index()

          nil ->
            do_rebuild_index()
        end
      end,
      [node()],
      retries
    )
    |> case do
      :aborted -> nil
      index -> index
    end
  end

  defp do_rebuild_index() do
    :ok = refresh_index()
    {_loaded_at, index} = :persistent_term.get(@index_key)
    index
  end

  defp fresh?(loaded_at), do: now_ms() - loaded_at < @index_ttl_ms

  @doc false
  # Articles with their questions and the normalized words used for matching,
  # plus the vocabulary of all words, so each query token is compared with each
  # distinct word once per lookup.
  @spec build_index() :: %{articles: [map()], vocabulary: [{String.t(), String.t()}]}
  def build_index() do
    headings = headings_by_article()

    articles =
      from(a in AcademyArticle,
        where: a.is_stale == false and a.suggested_questions != ^[],
        select: %{
          id: a.id,
          title: a.title,
          url: a.academy_url,
          questions: a.suggested_questions
        }
      )
      |> Repo.all()
      |> Enum.map(fn article ->
        title_words = Enum.uniq(words(article.title))

        context_words =
          (title_words ++ Enum.flat_map(Map.get(headings, article.id, []), &words/1))
          |> Enum.uniq()

        questions =
          Enum.map(article.questions, fn question ->
            question_words = words(question)

            %{
              article_id: article.id,
              title: article.title,
              url: article.url,
              question: question,
              words: Enum.uniq(question_words),
              text: Enum.join(question_words, " ")
            }
          end)

        %{title_words: title_words, context_words: context_words, questions: questions}
      end)

    vocabulary =
      articles
      |> Enum.flat_map(fn a -> a.context_words ++ Enum.flat_map(a.questions, & &1.words) end)
      |> Enum.uniq()
      |> Enum.map(&{&1, singular(&1)})

    %{articles: articles, vocabulary: vocabulary}
  end

  defp headings_by_article() do
    from(c in AcademyArticleChunk,
      where: c.is_stale == false and not is_nil(c.heading),
      distinct: true,
      select: {c.article_id, c.heading}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  # %{word => kind} for every vocabulary word the token matches. Kinds, strongest
  # first: 3 exact (or singular/plural), 2 prefix, 1 fuzzy.
  defp token_kinds({token, i}, tokens, vocabulary) do
    prefix? = i == length(tokens) - 1 or String.length(token) >= 4
    token = {token, singular(token), String.length(token) >= 4}

    Enum.reduce(vocabulary, %{}, fn {word, _} = entry, acc ->
      case match_kind(token, entry, prefix?) do
        0 -> acc
        kind -> Map.put(acc, word, kind)
      end
    end)
  end

  # Returns `{matched_tokens, score, entry}` per question. A question-word match
  # weighs twice a title/heading match.
  defp score_article(article, tokens, token_kinds) do
    context = Enum.map(token_kinds, &best_kind(&1, article.context_words))
    in_title? = Enum.all?(token_kinds, &(best_kind(&1, article.title_words) > 0))
    phrase = Enum.join(tokens, " ")

    Enum.map(article.questions, fn entry ->
      per_token =
        token_kinds
        |> Enum.zip(context)
        |> Enum.map(fn {kinds, in_context} -> {best_kind(kinds, entry.words), in_context} end)

      matched = Enum.count(per_token, fn {q, c} -> q > 0 or c > 0 end)
      score = Enum.reduce(per_token, 0, fn {q, c}, acc -> acc + 2 * q + c end)
      # The user is typing this question ("rate limits", "api key").
      phrase_bonus =
        if length(tokens) > 1 and String.contains?(entry.text, phrase), do: 3, else: 0

      # The query names the article ("mvrv", "dead address").
      title_bonus = if in_title?, do: 2, else: 0

      {matched, score + phrase_bonus + title_bonus, entry}
    end)
  end

  defp best_kind(kinds, words) do
    Enum.reduce_while(words, 0, fn word, best ->
      case Map.get(kinds, word, 0) do
        3 -> {:halt, 3}
        kind -> {:cont, max(kind, best)}
      end
    end)
  end

  defp match_kind({token, token_singular, fuzzy?}, {word, word_singular}, prefix?) do
    cond do
      token == word or token_singular == word_singular -> 3
      prefix? and String.starts_with?(word, token) -> 2
      fuzzy? and fuzzy?(token, word) -> 1
      true -> 0
    end
  end

  # Cheap byte checks first: jaro only runs for words with the same first letter
  # and a similar length.
  defp fuzzy?(<<first, _::binary>> = token, <<first, _::binary>> = word) do
    abs(byte_size(token) - byte_size(word)) <= 2 and
      String.jaro_distance(token, word) >= @fuzzy_threshold
  end

  defp fuzzy?(_token, _word), do: false

  defp singular(word) do
    if byte_size(word) > 3 and String.ends_with?(word, "s"),
      do: binary_part(word, 0, byte_size(word) - 1),
      else: word
  end

  # Words that carry meaning. "how do i" alone keeps its words, otherwise
  # stopwords are dropped so "what is mvrv" matches on "mvrv" only.
  defp query_tokens(query) do
    words = words(query)

    case Enum.reject(words, &(&1 in @stopwords)) do
      [] -> if String.length(Enum.join(words)) >= 2, do: words, else: []
      tokens -> tokens
    end
  end

  defp words(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, " ")
    |> String.split(" ", trim: true)
  end

  defp cap_per_article(scored) do
    {kept, _counts} =
      Enum.reduce(scored, {[], %{}}, fn {_matched, _score, entry} = item, {kept, counts} ->
        count = Map.get(counts, entry.article_id, 0)
        duplicate? = Enum.any?(kept, fn {_, _, e} -> e.question == entry.question end)

        if count < @max_per_article and not duplicate?,
          do: {[item | kept], Map.put(counts, entry.article_id, count + 1)},
          else: {kept, counts}
      end)

    Enum.reverse(kept)
  end

  defp now_ms(), do: System.monotonic_time(:millisecond)

  # Generation -----------------------------------------------------------

  @doc """
  Generate and store suggested questions. Manual: nothing calls this on a schedule.

  Options:
    * `:stale` - also regenerate articles whose content changed since their
      questions were generated (default false)
    * `:force` - regenerate all articles (default false)
    * `:ids` - only these article ids (regenerated even if they have questions)
    * `:dry_run` - return the generated questions without storing them
    * `:concurrency` - parallel LLM calls (default #{@default_concurrency})
    * `:model` - OpenAI model (default `#{@model}`)

  Returns `%{generated: n, skipped: n, failed: [{article_id, reason}]}`, plus
  `:questions` (`[{title, questions}]`) on a dry run.
  """
  @spec generate(keyword()) :: map()
  def generate(opts \\ []) do
    dry_run? = Keyword.get(opts, :dry_run, false)
    generate_fun = Keyword.get(opts, :generate_fun, &llm_questions(&1, opts))

    results =
      opts
      |> articles_to_generate()
      |> Task.async_stream(
        fn article -> {article, generate_for_article(article, generate_fun, dry_run?)} end,
        max_concurrency: Keyword.get(opts, :concurrency, @default_concurrency),
        timeout: :infinity,
        ordered: false
      )
      |> Enum.map(fn {:ok, result} -> result end)

    unless dry_run?, do: refresh_index()

    summary = %{
      generated: Enum.count(results, &match?({_, {:ok, _}}, &1)),
      skipped: Enum.count(results, &match?({_, :skipped}, &1)),
      failed: for({article, {:error, reason}} <- results, do: {article.id, reason})
    }

    Logger.info(
      "[AcademyQuestions] generated=#{summary.generated} skipped=#{summary.skipped} " <>
        "failed=#{length(summary.failed)}"
    )

    if dry_run?,
      do:
        Map.put(
          summary,
          :questions,
          for({article, {:ok, questions}} <- results, do: {article.title, questions})
        ),
      else: summary
  end

  @doc "Counts of articles with, without and with stale questions."
  @spec stats() :: map()
  def stats() do
    from(a in AcademyArticle,
      where: a.is_stale == false,
      select: %{
        articles: count(a.id),
        with_questions: filter(count(a.id), a.suggested_questions != ^[]),
        without_questions: filter(count(a.id), a.suggested_questions == ^[]),
        stale_questions:
          filter(
            count(a.id),
            a.suggested_questions != ^[] and a.questions_content_sha != a.content_sha
          ),
        questions: sum(fragment("cardinality(?)", a.suggested_questions))
      }
    )
    |> Repo.one()
  end

  defp articles_to_generate(opts) do
    query = from(a in AcademyArticle, where: a.is_stale == false, order_by: a.id)

    query =
      cond do
        ids = Keyword.get(opts, :ids) ->
          where(query, [a], a.id in ^ids)

        Keyword.get(opts, :force, false) ->
          query

        Keyword.get(opts, :stale, false) ->
          where(
            query,
            [a],
            a.suggested_questions == ^[] or is_nil(a.questions_content_sha) or
              a.questions_content_sha != a.content_sha
          )

        true ->
          where(query, [a], a.suggested_questions == ^[])
      end

    Repo.all(query)
  end

  defp generate_for_article(article, generate_fun, dry_run?) do
    {text, headings} = article_text(article.id)

    if String.trim(text) == "" do
      :skipped
    else
      input = %{title: article.title, url: article.academy_url, headings: headings, text: text}

      with {:ok, questions} <- generate_fun.(input),
           :ok <- maybe_store(article, questions, dry_run?) do
        {:ok, questions}
      else
        {:error, reason} ->
          Logger.warning("[AcademyQuestions] article=#{article.id} failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp maybe_store(_article, _questions, true), do: :ok

  defp maybe_store(article, questions, false) do
    case article |> AcademyArticle.questions_changeset(questions) |> Repo.update() do
      {:ok, _} -> :ok
      {:error, changeset} -> {:error, changeset.errors}
    end
  end

  # The article as the index stores it: cleaned chunks in order, and its headings.
  defp article_text(article_id) do
    chunks =
      from(c in AcademyArticleChunk,
        where: c.article_id == ^article_id and c.is_stale == false,
        order_by: c.chunk_index,
        select: {c.content, c.heading}
      )
      |> Repo.all()

    text = chunks |> Enum.map_join("\n\n", &elem(&1, 0)) |> String.slice(0, @max_article_chars)
    headings = chunks |> Enum.map(&elem(&1, 1)) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    {text, headings}
  end

  defp llm_questions(input, opts) do
    body = %{
      "model" => Keyword.get(opts, :model, @model),
      "temperature" => 0,
      "response_format" => %{"type" => "json_object"},
      "messages" => [
        %{"role" => "system", "content" => system_prompt()},
        %{"role" => "user", "content" => user_prompt(input)}
      ]
    }

    case Req.post(@openai_url,
           json: body,
           headers: [{"authorization", "Bearer #{System.get_env("OPENAI_API_KEY")}"}],
           receive_timeout: 60_000,
           retry: :transient,
           max_retries: 2
         ) do
      {:ok, %{status: 200, body: %{"choices" => [%{"message" => %{"content" => content}} | _]}}} ->
        parse_questions(content)

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc false
  @spec parse_questions(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def parse_questions(content) do
    with {:ok, %{"questions" => questions}} when is_list(questions) <- Jason.decode(content) do
      questions =
        questions
        |> Enum.filter(&is_binary/1)
        |> Enum.map(&(&1 |> String.replace(~r/\s+/, " ") |> String.trim()))
        |> Enum.filter(fn q ->
          String.ends_with?(q, "?") and String.length(q) in 10..@max_question_chars
        end)
        |> Enum.uniq_by(&String.downcase/1)
        |> Enum.take(@questions_per_article)

      if questions == [], do: {:error, :no_valid_questions}, else: {:ok, questions}
    else
      _ -> {:error, {:invalid_response, String.slice(content, 0, 200)}}
    end
  end

  defp system_prompt() do
    """
    You write the questions that users type into the search box of the Santiment Academy, \
    the documentation for Santiment's crypto on-chain, social and financial metrics, the \
    Sanbase platform, the Santiment API and related tools. \
    Reply with JSON only: {"questions": ["...", "..."]}.
    """
  end

  defp user_prompt(input) do
    """
    Write #{@questions_per_article} questions that a user might ask and that this article answers directly.

    Rules:
    - Cover the article's different sections, not only its introduction.
    - Use the exact names the article uses for metrics, labels, products, plans, API fields and functions, so a user typing those names finds the question.
    - Each question stands on its own: name the subject instead of writing "this metric" or "this article".
    - Phrase them the way a user would ask, in plain English, at most 120 characters, ending with a question mark. Use a raw API field or formula only in a question about that field.
    - Only ask what the article answers.

    Title: #{input.title}
    URL: #{input.url}
    Sections: #{Enum.join(input.headings, "; ")}

    Article:
    #{input.text}
    """
  end
end
