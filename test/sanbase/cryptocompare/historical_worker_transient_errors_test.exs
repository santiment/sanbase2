defmodule Sanbase.Cryptocompare.HistoricalWorkerTransientErrorsTest do
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

  for worker <- @workers,
      {name, response} <- [
        {"503 Service Unavailable",
         {:ok, %HTTPoison.Response{status_code: 503, body: "Service Unavailable", headers: []}}},
        {"HTTP timeout", {:error, %HTTPoison.Error{reason: :timeout}}},
        {"HTTP/2 GOAWAY", {:error, %HTTPoison.Error{reason: {:goaway, :no_error}}}}
      ] do
    @worker worker
    @response response

    test "#{inspect(worker)} snoozes on #{name} instead of failing" do
      Sanbase.Mock.prepare_mock2(&HTTPoison.get/3, @response)
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:snooze, seconds} = @worker.perform(job(@worker))
        assert is_integer(seconds) and seconds > 0
      end)
    end
  end

  describe "Handler.handle_job_error/3" do
    @tag capture_log: true
    test "returns a permanent error instead of snoozing" do
      assert Sanbase.Cryptocompare.Handler.handle_job_error("API error: bad instrument", 1, "x") ==
               {:error, "API error: bad instrument"}
    end

    # hackney 4 negotiates HTTP/2, whose connection-level failures (server
    # shutting the connection down, a stream reset or refused) are transient.
    for reason <- [
          {:goaway, :no_error},
          {:goaway, :internal_error},
          {:stream_reset, :refused_stream},
          {:stream_error, :internal_error}
        ] do
      @reason reason

      @tag capture_log: true
      test "snoozes on the HTTP/2 error #{inspect(reason)}" do
        error = %HTTPoison.Error{reason: @reason}

        assert {:snooze, 60} = Sanbase.Cryptocompare.Handler.handle_job_error(error, 1, "x")
      end
    end

    @tag capture_log: true
    test "does not snooze on an unknown HTTP error reason" do
      error = %HTTPoison.Error{reason: :nxdomain}

      assert Sanbase.Cryptocompare.Handler.handle_job_error(error, 1, "x") == {:error, error}
    end

    @tag capture_log: true
    test "returns a transient error once the snooze attempts are used up" do
      assert Sanbase.Cryptocompare.Handler.handle_job_error(:service_unavailable, 9, "x") ==
               {:error, :service_unavailable}
    end
  end
end
