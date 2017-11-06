defmodule Sanbase.DateTimeUtils do
  def seconds_ago(seconds) do
    DateTime.utc_now()
    |> DateTime.to_unix()
    |> Kernel.-(seconds)
    |> DateTime.from_unix!
  end
end
