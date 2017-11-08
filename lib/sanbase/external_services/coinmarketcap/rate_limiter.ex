defmodule Sanbase.ExternalServices.Coinmarketcap.RateLimiter do
  # A rate limiter for Coinmarketcap

  use GenServer, restart: :permanent, shutdown: 5_000

  # Allow max 10 requests per 60 seconds. Wait 4 seconds before
  # executing each request. 
  @scale 60_000
  @limit 10
  @time_between_requests 4000 #miliseconds
  @bucket "Coinmarketcap API Rate Limit"
  

  @name {:global, :coinmarketcap_rate_limiter}
  
  def start_link(_state) do
    IO.puts("Starting CMC rate limiter")
    GenServer.start_link(__MODULE__, :ok, name: @name)
  end

  def wait() do
    GenServer.call(@name, :wait, :infinity)
  end

  def sleep_algorithm ({:allow, count}) do
    Process.sleep(@time_between_requests)
    {:ok, count}
  end

  def sleep_algorithm ({:deny, _}) do
    {:ok, {_,_,wait_period, _, _}} = Hammer.inspect_bucket(@bucket, @scale, @limit)
    IO.puts("Denied!" <> to_string(wait_period))

    Process.sleep(wait_period)
    sleep_algorithm(Hammer.check_rate(@bucket, @scale, @limit))
  end
    

  def handle_call(:wait, _from, _state) do
    result = sleep_algorithm(Hammer.check_rate(@bucket, @scale, @limit))
    {:reply, result, nil} 
  end
  
end
