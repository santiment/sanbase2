defmodule Sanbase.SocialData do
  @moduledoc false
  import Sanbase.Utils.ErrorHandling, only: [error_result: 1]
  import Sanbase.Utils.Transform, only: [wrap_ok: 1]

  alias Sanbase.SocialData.ActiveUsers
  alias Sanbase.SocialData.Community
  alias Sanbase.SocialData.Sentiment
  alias Sanbase.SocialData.SocialDominance
  alias Sanbase.SocialData.SocialVolume
  alias Sanbase.Utils.Config

  require Logger
  require Mockery.Macro

  defp http_client, do: Mockery.Macro.mockable(HTTPoison)

  @recv_timeout 15_000

  defdelegate social_dominance(selector, datetime_from, datetime_to, interval, source),
    to: SocialDominance

  defdelegate social_volume(selector, from, to, interval, source),
    to: SocialVolume

  defdelegate social_volume(selector, from, to, interval, source, opts),
    to: SocialVolume

  defdelegate social_active_users(selector, from, to, interval),
    to: ActiveUsers

  defdelegate sentiment(selector, from, to, interval, source, type),
    to: Sentiment

  defdelegate social_volume_projects(), to: SocialVolume

  defdelegate community_messages_count(slug, from, to, interval, source),
    to: Community

  def word_context(words, source, size, from_datetime, to_datetime) when is_list(words) do
    words = Enum.reject(words, &(&1 == "***"))
    words_str = Enum.join(words, ",")

    words
    |> words_context_request(source, size, from_datetime, to_datetime)
    |> handle_response(&words_context_result/1, "word context", "words: #{words_str}")
  end

  def word_context(word, source, size, from_datetime, to_datetime) do
    word
    |> word_context_request(source, size, from_datetime, to_datetime)
    |> handle_response(&word_context_result/1, "word context", "word: #{word}")
  end

  def word_trend_score(word, source, from_datetime, to_datetime) do
    word
    |> word_trend_score_request(source, from_datetime, to_datetime)
    |> handle_response(&word_trend_score_result/1, "word trend score", "word: #{word}")
  end

  # Private functions

  defp words_context_request(words, source, size, from_datetime, to_datetime) when is_list(words) do
    from_unix = DateTime.to_unix(from_datetime)
    to_unix = DateTime.to_unix(to_datetime)

    url = "#{tech_indicators_url()}/indicator/words_context"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"words", Enum.join(words, ",")},
        {"size", size},
        {"source", Atom.to_string(source)},
        {"from_timestamp", from_unix},
        {"to_timestamp", to_unix}
      ]
    ]

    http_client().get(url, [], options)
  end

  defp word_context_request(word, source, size, from_datetime, to_datetime) do
    from_unix = DateTime.to_unix(from_datetime)
    to_unix = DateTime.to_unix(to_datetime)

    url = "#{tech_indicators_url()}/indicator/word_context"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"word", word},
        {"size", size},
        {"source", Atom.to_string(source)},
        {"from_timestamp", from_unix},
        {"to_timestamp", to_unix}
      ]
    ]

    http_client().get(url, [], options)
  end

  defp word_trend_score_request(word, source, from_datetime, to_datetime) do
    from_unix = DateTime.to_unix(from_datetime)
    to_unix = DateTime.to_unix(to_datetime)

    url = "#{tech_indicators_url()}/indicator/word_trend_score"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"word", word},
        {"source", Atom.to_string(source)},
        {"from_timestamp", from_unix},
        {"to_timestamp", to_unix}
      ]
    ]

    http_client().get(url, [], options)
  end

  defp word_context_result(result) do
    result
    |> Enum.map(fn {k, v} -> %{word: k, score: v["score"]} end)
    |> Enum.sort(&(&1.score >= &2.score))
    |> wrap_ok()
  end

  defp words_context_result(result) do
    result
    |> Enum.map(fn {word, context} ->
      {:ok, context} = word_context_result(context)

      %{
        word: word,
        context: context
      }
    end)
    |> wrap_ok()
  end

  defp word_trend_score_result(result) do
    result
    |> Enum.map(fn
      %{"timestamp" => timestamp, "score" => score, "hour" => hour, "source" => source} ->
        %{
          datetime: combine_unix_dt_and_hour(timestamp, hour),
          score: score,
          source: String.to_existing_atom(source)
        }
    end)
    |> Enum.sort(&(&1.score >= &2.score))
    |> wrap_ok()
  end

  defp handle_response(response, handle_callback, query_name_str, arg_str) do
    case response do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Jason.decode(body)
        handle_callback.(result)

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        error_result("Error status #{status} fetching #{query_name_str} for #{arg_str}: #{body}")

      {:error, %HTTPoison.Error{} = error} ->
        error_result("Cannot fetch #{query_name_str} for #{arg_str}: #{HTTPoison.Error.message(error)}")
    end
  end

  defp tech_indicators_url do
    Config.module_get(Sanbase.TechIndicators, :url)
  end

  def combine_unix_dt_and_hour(unix_dt, hour) do
    unix_dt
    |> DateTime.from_unix!()
    |> Timex.beginning_of_day()
    |> Timex.shift(hours: Sanbase.Math.to_integer(hour))
  end
end
