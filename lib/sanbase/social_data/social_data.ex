defmodule Sanbase.SocialData do
  import Sanbase.Utils.ErrorHandling, only: [error_result: 1]

  alias Sanbase.DateTimeUtils

  require Logger
  require Sanbase.Utils.Config, as: Config

  require Mockery.Macro
  defp http_client, do: Mockery.Macro.mockable(HTTPoison)

  @recv_timeout 15_000

  def trending_words(
        source,
        size,
        hour,
        from_datetime,
        to_datetime
      ) do
    trending_words_request(
      source,
      size,
      hour,
      from_datetime,
      to_datetime
    )
    |> handle_response(&trending_words_result/1, "trending words", "source: #{source}")
  end

  def word_context(
        word,
        source,
        size,
        from_datetime,
        to_datetime
      ) do
    word_context_request(
      word,
      source,
      size,
      from_datetime,
      to_datetime
    )
    |> handle_response(&word_context_result/1, "word context", "word #{word}")
  end

  def word_trend_score(
        word,
        source,
        from_datetime,
        to_datetime
      ) do
    word_trend_score_request(
      word,
      source,
      from_datetime,
      to_datetime
    )
    |> handle_response(&word_trend_score_result/1, "word trend score", "word #{word}")
  end

  def top_social_gainers_losers(%{
        status: status,
        from: from,
        to: to,
        time_window: time_window,
        size: size
      }) do
    case validate_time_window(time_window) do
      {:ok, time_window_in_days_str} ->
        social_gainers_losers_request(status, from, to, time_window_in_days_str, size)
        |> handle_response(
          &top_social_gainers_losers_result/1,
          "top social gainers losers",
          "status: #{status}"
        )

      {:error, error} ->
        Logger.error(error)
        {:error, error}
    end
  end

  def social_gainers_losers_status(%{
        slug: slug,
        from: from,
        to: to,
        time_window: time_window
      }) do
    case validate_time_window(time_window) do
      {:ok, time_window_in_days_str} ->
        social_gainers_losers_status_request(slug, from, to, time_window_in_days_str)
        |> handle_response(
          &social_gainers_losers_status_result/1,
          "social gainers losers status",
          "slug: #{slug}"
        )

      {:error, error} ->
        Logger.error("Invalid argument in top_social_gainers_losers: #{inspect(error)}")
        {:error, error}
    end
  end

  # Private functions

  defp trending_words_request(
         source,
         size,
         hour,
         from_datetime,
         to_datetime
       ) do
    from_unix = DateTime.to_unix(from_datetime)
    to_unix = DateTime.to_unix(to_datetime)

    url = "#{tech_indicators_url()}/indicator/trending_words"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"source", source |> Atom.to_string()},
        {"n", size},
        {"hour", hour},
        {"from_timestamp", from_unix},
        {"to_timestamp", to_unix}
      ]
    ]

    http_client().get(url, [], options)
  end

  defp word_context_request(
         word,
         source,
         size,
         from_datetime,
         to_datetime
       ) do
    from_unix = DateTime.to_unix(from_datetime)
    to_unix = DateTime.to_unix(to_datetime)

    url = "#{tech_indicators_url()}/indicator/word_context"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"word", word},
        {"size", size},
        {"source", source |> Atom.to_string()},
        {"from_timestamp", from_unix},
        {"to_timestamp", to_unix}
      ]
    ]

    http_client().get(url, [], options)
  end

  defp word_trend_score_request(
         word,
         source,
         from_datetime,
         to_datetime
       ) do
    from_unix = DateTime.to_unix(from_datetime)
    to_unix = DateTime.to_unix(to_datetime)

    url = "#{tech_indicators_url()}/indicator/word_trend_score"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"word", word},
        {"source", source |> Atom.to_string()},
        {"from_timestamp", from_unix},
        {"to_timestamp", to_unix}
      ]
    ]

    http_client().get(url, [], options)
  end

  defp social_gainers_losers_request(
         status,
         from_datetime,
         to_datetime,
         time_window,
         size
       ) do
    from_unix = DateTime.to_unix(from_datetime)
    to_unix = DateTime.to_unix(to_datetime)

    url = "#{tech_indicators_url()}/indicator/social_gainers_losers"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"status", status |> Atom.to_string()},
        {"from_timestamp", from_unix},
        {"to_timestamp", to_unix},
        {"range", time_window},
        {"size", size}
      ]
    ]

    http_client().get(url, [], options)
  end

  defp social_gainers_losers_status_request(
         slug,
         from_datetime,
         to_datetime,
         time_window
       ) do
    from_unix = DateTime.to_unix(from_datetime)
    to_unix = DateTime.to_unix(to_datetime)

    url = "#{tech_indicators_url()}/indicator/social_gainers_losers_status"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"project", slug},
        {"from_timestamp", from_unix},
        {"to_timestamp", to_unix},
        {"range", time_window}
      ]
    ]

    http_client().get(url, [], options)
  end

  defp trending_words_result(result) do
    result =
      result
      |> Enum.map(fn %{"timestamp" => timestamp, "top_words" => top_words} ->
        %{
          datetime: DateTime.from_unix!(timestamp),
          top_words:
            top_words
            |> Enum.map(fn {k, v} ->
              %{word: k, score: v}
            end)
        }
      end)

    {:ok, result}
  end

  defp word_context_result(result) do
    result =
      result
      |> Enum.map(fn {k, v} -> %{word: k, score: v["score"]} end)
      |> Enum.sort(&(&1.score >= &2.score))

    {:ok, result}
  end

  defp word_trend_score_result(result) do
    result =
      result
      |> Enum.map(fn %{
                       "timestamp" => timestamp,
                       "score" => score,
                       "hour" => hour,
                       "source" => source
                     } ->
        %{
          datetime: combine_unix_dt_and_hour(timestamp, hour),
          score: score,
          source: String.to_existing_atom(source)
        }
      end)
      |> Enum.sort(&(&1.score >= &2.score))

    {:ok, result}
  end

  defp top_social_gainers_losers_result(result) do
    result =
      result
      |> Enum.sort(&(&1["timestamp"] <= &2["timestamp"]))
      |> Enum.map(fn %{
                       "timestamp" => timestamp,
                       "projects" => projects
                     } ->
        %{
          datetime: DateTime.from_unix!(timestamp),
          projects: convert_projects_result(projects)
        }
      end)

    {:ok, result}
  end

  defp social_gainers_losers_status_result(result) do
    result =
      result
      |> Enum.sort(&(&1["timestamp"] <= &2["timestamp"]))
      |> Enum.map(fn %{
                       "timestamp" => timestamp,
                       "status" => status,
                       "change" => change
                     } ->
        %{
          datetime: DateTime.from_unix!(timestamp),
          status: String.to_existing_atom(status),
          change: change
        }
      end)

    {:ok, result}
  end

  defp convert_projects_result(projects) do
    projects
    |> Enum.map(fn %{"project" => project, "change" => change} = project_change ->
      case Map.get(project_change, "status") do
        nil ->
          %{project: project, change: change}

        status ->
          %{project: project, change: change, status: String.to_existing_atom(status)}
      end
    end)
  end

  defp handle_response(response, handle_callback, query_name_str, arg_str) do
    response
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Jason.decode(body)
        handle_callback.(result)

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        error_result("Error status #{status} fetching #{query_name_str} for #{arg_str}: #{body}")

      {:error, %HTTPoison.Error{} = error} ->
        error_result(
          "Cannot fetch #{query_name_str} for #{arg_str}: #{HTTPoison.Error.message(error)}"
        )
    end
  end

  defp validate_time_window(time_window) do
    with {:valid_compound_duration?, true} <-
           {:valid_compound_duration?, DateTimeUtils.valid_compound_duration?(time_window)},
         time_window_in_days = DateTimeUtils.compound_duration_to_days(time_window),
         {:valid_time_window?, true} <-
           {:valid_time_window?, time_window_in_days >= 2 and time_window_in_days <= 30} do
      {:ok, "#{time_window_in_days}d"}
    else
      {:valid_compound_duration?, false} ->
        {:error,
         "Invalid string format for time_window. Valid values can be - for ex: `2d`, `5d`, `1w`"}

      {:valid_time_window?, false} ->
        {:error,
         "Invalid `time_window` argument. time_window should be between 2 and 30 days - for ex: `2d`, `5d`, `1w`"}
    end
  end

  defp tech_indicators_url() do
    Config.module_get(Sanbase.TechIndicators, :url)
  end

  def combine_unix_dt_and_hour(unix_dt, hour) do
    unix_dt
    |> DateTime.from_unix!()
    |> Timex.beginning_of_day()
    |> Timex.shift(hours: Sanbase.Math.to_integer(hour))
  end
end
