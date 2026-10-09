defmodule Sanbase.Cryptocompare.HistoricalWorkerTransientErrorsTest do
  @moduledoc ~s"""
  Reproduces SANBASE-BACKEND-PROD-G51/G52 ({:error, :service_unavailable}) and
  SANBASE-BACKEND-PROD-G6H/G79 (HTTPoison.Error :timeout).

  A 503 or an HTTP timeout from the Cryptocompare API is a transient condition.
  Returning `{:error, _}` makes Oban emit a `[:oban, :job, :exception]` event on
  every attempt, which the Sentry Oban integration reports as an error. The
  workers should snooze the job instead, so it is retried later without being
  reported as a failure.
  """
  use Sanbase.DataCase, async: false

  alias Sanbase.Cryptocompare.OpenInterest
  alias Sanbase.Cryptocompare.FundingRate

  @workers [OpenInterest.HistoricalWorker, FundingRate.HistoricalWorker]

  defp job(worker) do
    %Oban.Job{
      id: 1,
      attempt: 1,
      max_attempts: 20,
      worker: inspect(worker),
      args: %{
        "market" => "binance",
        "instrument" => "ETC-USDT-VANILLA-PERPETUAL",
        "timestamp" => 1_791_532_801,
        "limit" => 500,
        "schedule_next_job" => false,
        "version" => "v1"
      }
    }
  end

  for worker <- @workers do
    @worker worker

    test "#{inspect(worker)} snoozes on 503 Service Unavailable instead of failing" do
      Sanbase.Mock.prepare_mock(HTTPoison, :get, fn _url, _headers, _opts ->
        {:ok, %HTTPoison.Response{status_code: 503, body: "Service Unavailable", headers: []}}
      end)
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:snooze, seconds} = @worker.perform(job(@worker))
        assert is_integer(seconds) and seconds > 0
      end)
    end

    test "#{inspect(worker)} snoozes on HTTP timeout instead of failing" do
      Sanbase.Mock.prepare_mock(HTTPoison, :get, fn _url, _headers, _opts ->
        {:error, %HTTPoison.Error{reason: :timeout}}
      end)
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:snooze, seconds} = @worker.perform(job(@worker))
        assert is_integer(seconds) and seconds > 0
      end)
    end
  end
end
