defmodule Sanbase.Scrapers.Scheduler do
  use Quantum.Scheduler,
    otp_app: :sanbase
end

defmodule Sanbase.Signals.Scheduler do
  use Quantum.Scheduler,
    otp_app: :sanbase
end
