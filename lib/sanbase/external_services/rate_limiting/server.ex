defmodule Sanbase.ExternalServices.RateLimiting.Server do
  # A rate limiter for Etherscan

  use GenServer, restart: :permanent, shutdown: 5_000
  require Logger

  # Allow max 5 requests per 1 second. Wait 1 second before
  # executing each request.
  # (This is for testing purposes. For production
  @default_scale 1000
  @default_limit 5
  @default_time_between_requests 1000 #miliseconds

  def child_spec(name, options \\ []) do
    %{
      id: name,
      start: {
        Sanbase.ExternalServices.RateLimiting.Server,
        :start_link,
        [Keyword.put(options, :name, name)]
      }
    }
  end

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: Keyword.get(options, :name))
  end

  def init(options) do
    scale = Keyword.get(options, :scale, @default_scale)
    limit = Keyword.get(options, :limit, @default_limit)
    time_between_requests = Keyword.get(options, :time_between_requests, @default_time_between_requests)
    bucket = Keyword.get(options, :name)

    Logger.info fn ->
      "Rate limiter started. Bucket: #{bucket}"
    end

    {:ok, {bucket, scale, limit, time_between_requests}}
  end


  def wait(name) do
    GenServer.call(name, :wait, :infinity)
  end


  def sleep_algorithm({_bucket,_,_,time_between_requests}, {:allow, count}) do
    Process.sleep(time_between_requests)
    {:ok, count}
  end


  def sleep_algorithm({bucket, scale, limit, _} = state, {:deny, _}) do
    {:ok, {_,_,wait_period, _, _}} = Hammer.inspect_bucket(bucket, scale, limit)
    Logger.info fn ->
      "Rate limit exceeded. bucket: #{bucket}, wait_period: #{wait_period}"
    end

    Process.sleep(wait_period)
    sleep_algorithm(state, Hammer.check_rate(bucket, scale, limit))
  end

  def handle_call(:wait, _, {bucket, scale, limit, _} = state) do
    result = sleep_algorithm(state, Hammer.check_rate(bucket, scale, limit))
    {:reply, result, state}
  end

end
