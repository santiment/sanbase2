defmodule Sanbase.Scrapers.Scheduler do
  use Quantum,
    otp_app: :sanbase

  def enabled?() do
    System.get_env("QUANTUM_SCHEDULER_ENABLED", "false") |> String.to_existing_atom()
  end
end

defmodule Sanbase.Signals.Scheduler do
  use Quantum,
    otp_app: :sanbase

  def enabled?() do
    System.get_env("QUANTUM_SCHEDULER_ENABLED", "false") |> String.to_existing_atom()
  end
end
