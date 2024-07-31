defmodule Sanbase.ExternalServices.Coinmarketcap.Utils do
  # After invocation of this function the process should execute `Process.exit(self(), :normal)`
  # There is no meaningful result to be returned here. If it does not exit
  # this case should return a special case and it should be handeled so the
  # `last_updated` is not updated when no points are written
  def wait_rate_limit(%Tesla.Env{status: 429, headers: headers}, rate_limiting_server) do
    wait_period =
      case Enum.find(headers, &match?({"retry-after", _}, &1)) do
        {_, wait_period} -> wait_period |> String.to_integer()
        _ -> 1
      end

    wait_until = Timex.shift(Timex.now(), seconds: wait_period)
    Sanbase.ExternalServices.RateLimiting.Server.wait_until(rate_limiting_server, wait_until)
  end
end
