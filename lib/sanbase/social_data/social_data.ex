defmodule Sanbase.SocialData.SocialData do
  import Sanbase.Utils.ErrorHandling, only: [error_result: 1]

  require Logger
  require Sanbase.Utils.Config, as: Config

  alias Sanbase.Model.Project

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
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Jason.decode(body)

        trending_words_result(result)

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        error_result("Error status #{status} fetching trending words for source: #{source}: #{body}")

      {:error, %HTTPoison.Error{} = error} ->
        error_result(
          "Cannot fetch trending words data for source #{source}: #{HTTPoison.Error.message(error)}"
        )
    end
  end

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
        {"source", source},
        {"n", size},
        {"hour", hour},
        {"from_timestamp", from_unix},
        {"to_timestamp", to_unix}
      ]
    ]

    http_client().get(url, [], options)
  end

  defp trending_words_result(result) do
    result =
      result
      |> Enum.map(fn %{"timestamp" => timestamp, "top_words" => top_words} ->
        %{datetime: DateTime.from_unix!(timestamp),
          words: top_words |> Enum.map(fn ({k, v}) ->
            %{word: k,
              score: v}
          end)}
      end)

    {:ok, result}
  end

  defp tech_indicators_url() do
    Config.module_get(Sanbase.TechIndicators, :url)
  end
end
