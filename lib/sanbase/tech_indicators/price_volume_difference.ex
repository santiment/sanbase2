defmodule Sanbase.TechIndicators.PriceVolumeDifference do
  import Sanbase.Utils.ErrorHandling

  require Logger
  require Sanbase.Utils.Config, as: Config

  alias Sanbase.Model.Project

  require Mockery.Macro
  defp http_client, do: Mockery.Macro.mockable(HTTPoison)

  @recv_timeout 15_000

  @type price_volume_diff_point :: %{
          datetime: DateTime.t(),
          price_volume_diff: number() | nil,
          price_change: number() | nil,
          volume_change: number() | nil
        }

  @spec price_volume_diff(
          %Project{},
          String.t(),
          DateTime.t(),
          DateTime.t(),
          String.t(),
          String.t(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: {:error, String.t()} | {:ok, [price_volume_diff_point()]}
  def price_volume_diff(
        %Project{ticker: ticker, coinmarketcap_id: slug} = project,
        currency,
        from,
        to,
        aggregate_interval,
        window_type,
        approximation_window,
        comparison_window,
        result_size_tail \\ 0
      ) do
    url = "#{tech_indicators_url()}/indicator/pricevolumediff/ma"

    # Workaround an issue with the usability of the tech_indicators api.
    # The calculation needs to start from before the `from` so the
    # moving average can be calculated for the specified time. Shift the datetime
    # and drop the same number of points from the result
    shifted_from =
      Timex.shift(from,
        seconds:
          -Sanbase.DateTimeUtils.compound_duration_to_seconds(aggregate_interval) *
            (approximation_window + comparison_window)
      )

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"ticker_slug", ticker <> "_" <> slug},
        {"currency", currency},
        {"from_timestamp", DateTime.to_unix(shifted_from)},
        {"to_timestamp", DateTime.to_unix(to)},
        {"aggregate_interval", aggregate_interval},
        {"window_type", window_type},
        {"approximation_window", approximation_window},
        {"comparison_window", comparison_window},
        {"result_size_tail", result_size_tail}
      ]
    ]

    http_client().get(url, [], options)
    |> handle_result(project)
    |> case do
      {:ok, result} ->
        {:ok,
         Enum.drop_while(result, fn %{datetime: datetime} ->
           DateTime.compare(datetime, from) == :lt
         end)}

      {:error, error} ->
        {:error, error}
    end
  end

  defp handle_result({:ok, %HTTPoison.Response{status_code: 200, body: body}}, _project) do
    {:ok, result} = Jason.decode(body)
    price_volume_diff_result(result)
  end

  defp handle_result({:ok, %HTTPoison.Response{status_code: status, body: body}}, project) do
    warn_result(
      "Error status #{status} fetching price-volume diff for #{Project.describe(project)} - #{body}"
    )
  end

  defp handle_result({:error, %HTTPoison.Error{} = error}, project) do
    error_result(
      "Cannot fetch price-volume diff data for #{Project.describe(project)} - #{
        HTTPoison.Error.message(error)
      }"
    )
  end

  defp price_volume_diff_result(result) do
    result =
      result
      |> Enum.map(fn %{
                       "timestamp" => timestamp,
                       "price_volume_diff" => price_volume_diff,
                       "price_change" => price_change,
                       "volume_change" => volume_change
                     } ->
        %{
          datetime: DateTime.from_unix!(timestamp),
          price_volume_diff: price_volume_diff,
          price_change: price_change,
          volume_change: volume_change
        }
      end)

    {:ok, result}
  end

  defp tech_indicators_url(), do: Config.module_get(Sanbase.TechIndicators, :url)
end
