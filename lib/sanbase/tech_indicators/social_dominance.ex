defmodule Sanbase.TechIndicators.SocialDominance do
  import Sanbase.Utils.ErrorHandling

  alias Sanbase.Model.Project

  require Mockery.Macro
  defp http_client, do: Mockery.Macro.mockable(HTTPoison)

  require Sanbase.Utils.Config, as: Config

  @recv_timeout 15_000

  def social_dominance(
        slug,
        datetime_from,
        datetime_to,
        interval,
        social_volume_type
      ) do
    social_dominance_request(
      slug,
      datetime_from,
      datetime_to,
      interval,
      social_volume_type
    )
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Jason.decode(body)
        parse_result(result)

      {:ok, %HTTPoison.Response{status_code: status}} ->
        warn_result("Error status #{status} fetching social dominance for project #{slug}")

      {:error, %HTTPoison.Error{} = error} ->
        error_result(
          "Cannot fetch social dominance data for project #{slug}: #{HTTPoison.Error.message(error)}"
        )
    end
  end

  defp social_dominance_request(
         slug,
         datetime_from,
         datetime_to,
         interval,
         social_volume_type
       ) do
    from_unix = DateTime.to_unix(datetime_from)
    to_unix = DateTime.to_unix(datetime_to)
    ticker = Project.ticker_by_slug(slug)
    ticker_slug = "#{ticker}_#{slug}"

    url = "#{tech_indicators_url()}/indicator/#{social_volume_type}"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"project", ticker_slug},
        {"datetime_from", from_unix},
        {"datetime_to", to_unix},
        {"interval", interval}
      ]
    ]

    http_client().get(url, [], options)
  end

  defp parse_result(result) do
    result =
      result
      |> Enum.map(fn %{
                       "timestamp" => timestamp,
                       "mentions_count" => mentions_count
                     } ->
        %{
          datetime: DateTime.from_unix!(timestamp),
          dominance: mentions_count
        }
      end)

    {:ok, result}
  end

  defp tech_indicators_url() do
    Config.module_get(Sanbase.TechIndicators, :url)
  end
end