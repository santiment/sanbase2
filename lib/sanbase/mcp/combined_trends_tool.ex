defmodule Sanbase.MCP.CombinedTrendsTool do
  @moduledoc """
  Combined trends tool that fetches trending words, stories, and documents in parallel.

  This tool provides a unified view of all trending data - words with their documents
  and stories - in a single response across all crypto projects.

  ## Parameters

  - `time_period` - Time period for trending data (e.g., '1h', '6h', '1d', '7d'). Defaults to '1h' (last hour).
  - `size` - Number of items per category to return (max 30). Defaults to 10.
  - `include_stories` - Include trending stories in response. Defaults to true.
  - `include_words` - Include trending words in response. Defaults to true.

  ## Response

  - `trends` - Combined trending data containing stories and words.
  - `metadata` - Request metadata including time period, size, and included data types.
  - `errors` - Any non-fatal errors encountered during data fetching.

  ## Trending Data Structure

  ### Stories
  - `title` - Title of the trending story.
  - `summary` - Summary of the story.
  - `score` - Trending score.
  - `query` - Search query used to find the story.
  - `related_tokens` - List of related crypto tokens (format: "BTC_bitcoin").
  - `bullish_sentiment_ratio` - Bullish sentiment ratio.
  - `bearish_sentiment_ratio` - Bearish sentiment ratio.

  ### Words
  - `word` - The trending word.
  - `score` - Trending score.
  - `slug` - Associated project slug (if word is project-related).
  - `summary` - AI-generated summary of discussions.
  - `bullish_summary` - Summary of bullish sentiment.
  - `bearish_summary` - Summary of bearish sentiment.
  - `positive_sentiment_ratio` - Positive sentiment ratio.
  - `negative_sentiment_ratio` - Negative sentiment ratio.
  - `neutral_sentiment_ratio` - Neutral sentiment ratio.
  - `positive_bb_sentiment_ratio` - Positive bull/bear sentiment ratio.
  - `negative_bb_sentiment_ratio` - Negative bull/bear sentiment ratio.
  - `neutral_bb_sentiment_ratio` - Neutral bull/bear sentiment ratio.
  - `context` - Related words that appear with this trending word.
  - `documents_summary` - AI-generated summary of related social media discussions.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Sanbase.SocialData.{TrendingWords, TrendingStories, SocialDocument}
  alias Sanbase.AI.OpenAIClient
  alias Sanbase.MCP.Utils

  require Logger

  schema do
    field(:time_period, :string,
      required: false,
      description: """
      Time period for trending data (e.g., '1h', '6h', '1d', '7d').
      This parameter defines how far back to look for trending data.

      Defaults to '1h' (last hour).
      """
    )

    field(:size, :integer,
      required: false,
      description: """
      Number of items per category to return (max 30).

      Defaults to 10.
      """
    )

    field(:include_stories, :boolean,
      required: false,
      description: """
      Include trending stories in the response.

      Defaults to true.
      """
    )

    field(:include_words, :boolean,
      required: false,
      description: """
      Include trending words in the response.

      Defaults to true.
      """
    )
  end

  @impl true
  def execute(params, frame) do
    do_execute(params, frame)
  end

  defp do_execute(params, frame) do
    time_period = params[:time_period] || "1h"
    size = params[:size] || 10
    include_stories = Map.get(params, :include_stories, true)
    include_words = Map.get(params, :include_words, true)

    with {:ok, {from_datetime, to_datetime}} <- Utils.parse_time_period(time_period),
         {:ok, validated_size} <- Utils.validate_size(size, 1, 10) do
      # Fetch data in parallel with graceful error handling
      {trends_data, errors} =
        fetch_all_trends_data(
          from_datetime,
          to_datetime,
          validated_size,
          include_stories,
          include_words
        )

      response_data = %{
        trends: trends_data,
        metadata: %{
          time_period: time_period,
          size: validated_size,
          period_start: DateTime.to_iso8601(from_datetime),
          period_end: DateTime.to_iso8601(to_datetime),
          included_data_types: build_included_types(include_stories, include_words)
        },
        errors: errors
      }

      {:reply, Response.json(Response.tool(), response_data), frame}
    else
      {:error, reason} ->
        {:reply, Response.error(Response.tool(), reason), frame}
    end
  end

  defp fetch_all_trends_data(
         from_datetime,
         to_datetime,
         size,
         include_stories,
         include_words
       ) do
    interval = determine_interval(from_datetime, to_datetime)

    # Launch parallel tasks for data fetching with explicit tracking
    stories_task =
      if include_stories do
        Task.async(fn ->
          {:stories, fetch_trending_stories_safe(from_datetime, to_datetime, interval, size)}
        end)
      else
        nil
      end

    words_task =
      if include_words do
        Task.async(fn ->
          {:words, fetch_trending_words_safe(from_datetime, to_datetime, interval, size)}
        end)
      else
        nil
      end

    # Collect non-nil tasks
    tasks = [stories_task, words_task] |> Enum.filter(& &1)

    # Wait for all tasks to complete
    # 30 second timeout
    results = Task.yield_many(tasks, 30_000)

    # Process results and collect errors using explicit data type identification
    {stories_data, stories_errors} = extract_typed_result(results, :stories, include_stories)
    {words_data, words_errors} = extract_typed_result(results, :words, include_words)

    # Fetch documents for trending words
    {enriched_words, document_errors} = enrich_words_with_documents(words_data)

    # Combine all data
    trends_data = %{}

    trends_data =
      if include_stories,
        do: Map.put(trends_data, :trending_stories, stories_data),
        else: trends_data

    trends_data =
      if include_words,
        do: Map.put(trends_data, :trending_words, enriched_words),
        else: trends_data

    # Collect all errors
    all_errors = stories_errors ++ words_errors ++ document_errors

    {trends_data, all_errors}
  end

  defp extract_typed_result(results, data_type, should_include) do
    if should_include do
      case Enum.find(results, fn {_task, result} ->
             case result do
               {:ok, {^data_type, _data}} -> true
               {^data_type, _data} -> true
               _ -> false
             end
           end) do
        {_task, {:ok, {^data_type, data}}} when is_list(data) ->
          {data, []}

        {_task, {^data_type, data}} when is_list(data) ->
          {data, []}

        {_task, {:ok, {^data_type, data}}} ->
          error_msg = "Unexpected data format for #{data_type}: #{inspect(data)}"
          Logger.warning(error_msg)
          {[], [error_msg]}

        {_task, {^data_type, data}} ->
          error_msg = "Unexpected data format for #{data_type}: #{inspect(data)}"
          Logger.warning(error_msg)
          {[], [error_msg]}

        {_task, {:error, error}} ->
          error_msg = "Failed to fetch #{data_type}: #{inspect(error)}"
          Logger.warning(error_msg)
          {[], [error_msg]}

        {_task, nil} ->
          error_msg = "Timeout fetching #{data_type}"
          Logger.warning(error_msg)
          {[], [error_msg]}

        nil ->
          error_msg = "No result found for #{data_type}"
          Logger.warning(error_msg)
          {[], [error_msg]}

        other ->
          error_msg = "Unexpected result format for #{data_type}: #{inspect(other)}"
          Logger.warning(error_msg)
          {[], [error_msg]}
      end
    else
      {[], []}
    end
  end

  defp fetch_trending_stories_safe(from_datetime, to_datetime, interval, size) do
    case TrendingStories.get_trending_stories(from_datetime, to_datetime, interval, size) do
      {:ok, stories_map} ->
        formatted_stories =
          stories_map
          |> Enum.sort_by(fn {datetime, _} -> datetime end, {:asc, DateTime})
          |> Enum.map(fn {datetime, top_stories} ->
            %{
              datetime: DateTime.to_iso8601(datetime),
              top_stories: Enum.map(top_stories, &format_story/1)
            }
          end)

        formatted_stories

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_trending_words_safe(from_datetime, to_datetime, interval, size) do
    case TrendingWords.get_trending_words(from_datetime, to_datetime, interval, size, :all, :all) do
      {:ok, words_map} ->
        words_data =
          words_map
          |> Enum.sort_by(fn {datetime, _} -> datetime end, {:asc, DateTime})
          |> Enum.map(fn {datetime, top_words} ->
            %{
              datetime: DateTime.to_iso8601(datetime),
              top_words: top_words
            }
          end)

        words_data

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp enrich_words_with_documents(words_data) when is_list(words_data) do
    # Step 1: Collect all words and fetch their documents
    collect_start_time = System.monotonic_time(:millisecond)
    Logger.info("📄 Starting document collection...")
    all_words_with_docs = collect_words_and_documents(words_data)
    collect_end_time = System.monotonic_time(:millisecond)
    collect_duration_ms = collect_end_time - collect_start_time

    Logger.info(
      "📄 Document collection completed in: #{collect_duration_ms}ms (#{Float.round(collect_duration_ms / 1000, 2)}s)"
    )

    Logger.info("📊 Collected documents for #{length(all_words_with_docs)} words")

    # Step 2: Batch summarize all words and documents in one OpenAI call
    word_summaries = batch_summarize_documents_with_ai(all_words_with_docs)

    # Step 3: Apply summaries back to the word data structure
    enriched_words =
      Enum.map(words_data, fn period_data ->
        case period_data do
          %{top_words: top_words} when is_list(top_words) ->
            enriched_top_words =
              top_words
              |> Enum.map(fn word ->
                summary = Map.get(word_summaries, word.word, "No summary available.")
                Map.put(word, :documents_summary, summary)
              end)
              |> Enum.map(&format_word/1)

            %{period_data | top_words: enriched_top_words}

          other ->
            Logger.warning(
              "Unexpected period_data format in enrich_words_with_documents: #{inspect(other)}"
            )

            period_data
        end
      end)

    {enriched_words, []}
  end

  defp enrich_words_with_documents(words_data) do
    error_msg = "Invalid words_data format for enrichment: #{inspect(words_data)}"
    Logger.warning(error_msg)
    {[], [error_msg]}
  end

  defp collect_words_and_documents(words_data) do
    words_data
    |> Enum.flat_map(fn period_data ->
      case period_data do
        %{top_words: top_words} when is_list(top_words) -> top_words
        _ -> []
      end
    end)
    # Remove duplicate words across time periods
    |> Enum.uniq_by(& &1.word)
    |> Enum.map(&fetch_word_documents/1)
    # Only words with documents
    |> Enum.filter(fn {_word, documents} -> String.trim(documents) != "" end)
  end

  defp fetch_word_documents(word) do
    case word.top_documents_ids do
      ids when is_list(ids) and ids != [] ->
        case SocialDocument.get_documents(ids) do
          {:ok, documents} when is_list(documents) and documents != [] ->
            document_texts =
              documents
              |> Enum.map(& &1.text)
              |> Enum.filter(&(&1 && String.trim(&1) != ""))
              |> Enum.join("\n")

            {word.word, document_texts}

          _ ->
            {word.word, ""}
        end

      _ ->
        {word.word, ""}
    end
  rescue
    error ->
      Logger.warning("Error fetching documents for word '#{word.word}': #{inspect(error)}")
      {word.word, ""}
  end

  defp batch_summarize_documents_with_ai(words_with_docs) do
    batch_start_time = System.monotonic_time(:millisecond)
    Logger.info("🚀 Starting batch AI summarization for #{length(words_with_docs)} words...")

    result = do_batch_summarize_documents_with_ai(words_with_docs)
    batch_end_time = System.monotonic_time(:millisecond)
    total_duration_ms = batch_end_time - batch_start_time

    Logger.info(
      "✅ Batch AI summarization completed in: #{total_duration_ms}ms (#{Float.round(total_duration_ms / 1000, 2)}s)"
    )

    result
  rescue
    error ->
      Logger.warning("Error in batch AI summarization: #{inspect(error)}")
      # Return fallback summaries for all words
      words_with_docs
      |> Enum.map(fn {word, docs} ->
        doc_count = String.split(docs, "\n") |> Enum.count(fn line -> String.trim(line) != "" end)

        {word,
         "Error generating summary. #{doc_count} documents found discussing this trending word."}
      end)
      |> Map.new()
  end

  defp do_batch_summarize_documents_with_ai([]), do: %{}

  defp do_batch_summarize_documents_with_ai(words_with_docs) when is_list(words_with_docs) do
    # Build a structured prompt for batch processing
    batch_content = build_batch_summary_prompt(words_with_docs)

    if String.trim(batch_content) == "" do
      %{}
    else
      system_prompt = """
      You are a helpful assistant that summarizes social media discussions about trending cryptocurrency words.
      You will receive multiple trending words with their associated social media posts.
      For each word, provide a concise summary of the discussions.

      Format your response as a JSON object where each key is the trending word and the value is the summary.
      Example: {"bitcoin": "Summary of bitcoin discussions...", "ethereum": "Summary of ethereum discussions..."}
      """

      start_time = System.monotonic_time(:millisecond)

      openai_result =
        openai_client().chat_completion(system_prompt, batch_content,
          max_tokens: 1000,
          temperature: 0.3
        )

      end_time = System.monotonic_time(:millisecond)
      duration_ms = end_time - start_time

      Logger.info(
        "⏱️  OpenAI API call took: #{duration_ms}ms (#{Float.round(duration_ms / 1000, 2)}s)"
      )

      case openai_result do
        {:ok, response} ->
          parse_batch_summary_response(response, words_with_docs)

        {:error, reason} ->
          Logger.warning("Failed to generate batch AI summaries: #{reason}")
          # Return fallback summaries
          words_with_docs
          |> Enum.map(fn {word, docs} ->
            doc_count =
              String.split(docs, "\n") |> Enum.count(fn line -> String.trim(line) != "" end)

            {word,
             "AI summarization temporarily unavailable. #{doc_count} documents found discussing this trending word."}
          end)
          |> Map.new()
      end
    end
  end

  defp build_batch_summary_prompt(words_with_docs) do
    words_with_docs
    |> Enum.map(fn {word, documents} ->
      # Truncate documents if too long to fit within token limits
      # Smaller per-word limit for batch processing
      truncated_docs = String.slice(documents, 0, 2000)

      """

      Word: #{word}
      Documents:
      #{truncated_docs}
      """
    end)
    |> Enum.join("\n---\n")
  end

  defp parse_batch_summary_response(response, words_with_docs) do
    case Jason.decode(String.trim(response)) do
      {:ok, summaries} when is_map(summaries) ->
        # Use AI summaries where available, fallback for missing ones
        words_with_docs
        |> Enum.map(fn {word, docs} ->
          summary =
            Map.get(summaries, word) ||
              Map.get(summaries, String.downcase(word)) ||
              generate_fallback_summary(word, docs)

          {word, summary}
        end)
        |> Map.new()

      _ ->
        Logger.warning("Failed to parse batch summary response as JSON: #{response}")
        # Return fallback summaries
        words_with_docs
        |> Enum.map(fn {word, docs} -> {word, generate_fallback_summary(word, docs)} end)
        |> Map.new()
    end
  end

  defp generate_fallback_summary(_word, docs) do
    doc_count = String.split(docs, "\n") |> Enum.count(fn line -> String.trim(line) != "" end)

    "AI summarization temporarily unavailable. #{doc_count} documents found discussing this trending word."
  end

  defp determine_interval(from_datetime, to_datetime) do
    diff_hours = DateTime.diff(to_datetime, from_datetime, :hour)

    cond do
      diff_hours <= 24 -> "1h"
      # 1 week
      diff_hours <= 168 -> "6h"
      true -> "1d"
    end
  end

  defp format_story(story) do
    %{
      title: story.title,
      summary: story.summary,
      score: story.score,
      query: story.search_text,
      related_tokens: story.related_tokens || [],
      bullish_sentiment_ratio: story.bullish_ratio,
      bearish_sentiment_ratio: story.bearish_ratio
    }
  end

  defp format_word(word) do
    %{
      word: word.word,
      score: word.score,
      slug: word.slug,
      summary: word.summary,
      bullish_summary: word.bullish_summary,
      bearish_summary: word.bearish_summary,
      positive_sentiment_ratio: word.positive_sentiment_ratio,
      negative_sentiment_ratio: word.negative_sentiment_ratio,
      neutral_sentiment_ratio: word.neutral_sentiment_ratio,
      positive_bb_sentiment_ratio: word.positive_bb_sentiment_ratio,
      negative_bb_sentiment_ratio: word.negative_bb_sentiment_ratio,
      neutral_bb_sentiment_ratio: word.neutral_bb_sentiment_ratio,
      context: word.context || [],
      documents_summary: word.documents_summary || "No document summary available."
    }
  end

  defp build_included_types(include_stories, include_words) do
    types = []
    types = if include_stories, do: ["stories" | types], else: types
    types = if include_words, do: ["words" | types], else: types
    types
  end

  defp openai_client do
    Application.get_env(:sanbase, :openai_client, OpenAIClient)
  end
end
