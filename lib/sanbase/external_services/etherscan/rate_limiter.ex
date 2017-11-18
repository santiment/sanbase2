defmodule Sanbase.ExternalServices.Etherscan.RateLimiter.Tesla do
  @behaviour Tesla.Middleware

  alias Sanbase.ExternalServices.Etherscan.RateLimiter
  def call(env, next, _) do
    RateLimiter.wait()
    Tesla.run(env, next)
  end
end

defmodule Sanbase.ExternalServices.Etherscan.RateLimiter do
  # A rate limiter for Etherscan

  use GenServer, restart: :permanent, shutdown: 5_000
  require Logger

  # Allow max 5 requests per 1 second. Wait 1 second before
  # executing each request.
  # (This is for testing purposes. For production
  @default_scale 1000
  @default_limit 5
  @default_time_between_requests 1000 #miliseconds

  @name {:global, :etherscan_rate_limiter}

  def start_link(_state) do
    GenServer.start_link(__MODULE__, :ok, name: @name)
  end

  def init(:ok) do
    scale = Keyword.get(config(), :scale, @default_scale)
    limit = Keyword.get(config(), :limit, @default_limit)
    time_between_requests = Keyword.get(config(), :time_between_requests, @default_time_between_requests)
    bucket = Keyword.get(config(), :bucket, Macro.to_string(quote do: unquote(@name)))

    Logger.info fn ->
      "Rate limiter started. Bucket: #{bucket}"
    end

    {:ok, {bucket, scale, limit, time_between_requests}}
  end


  def wait() do
    GenServer.call(@name, :wait, :infinity)
  end


  def sleep_algorithm({bucket,_,_,time_between_requests}, {:allow, count}) do
    Process.sleep(time_between_requests)
    {:ok, count}
  end


  def sleep_algorithm(state, {:deny, _}) do
    {bucket, scale, limit, _} = state
    {:ok, {_,_,wait_period, _, _}} = Hammer.inspect_bucket(bucket, scale, limit)
    Logger.info fn ->
      "Rate limit exceeded. bucket: #{bucket}, wait_period: #{wait_period}"
    end

    Process.sleep(wait_period)
    sleep_algorithm(state, Hammer.check_rate(bucket, scale, limit))
  end

  def handle_call(:wait, _, state) do
    {bucket, scale, limit, _} = state
    result = sleep_algorithm(state, Hammer.check_rate(bucket, scale, limit))
    {:reply, result, state}
  end

  def config do
    Application.get_env(:sanbase, __MODULE__)
  end

end
