defmodule Sanbase.Scrapers.Scheduler do
  @moduledoc false
  use Quantum,
    otp_app: :sanbase

  def enabled? do
    case System.get_env("QUANTUM_SCHEDULER_ENABLED", "false") do
      truthy when truthy in ["1", "true", true] -> true
      falsy when falsy in ["0", "false", false, nil] -> false
    end
  end
end

defmodule Sanbase.Alerts.Scheduler do
  @moduledoc false
  use Quantum,
    otp_app: :sanbase

  def enabled? do
    case System.get_env("QUANTUM_SCHEDULER_ENABLED", "false") do
      truthy when truthy in ["1", "true", true] -> true
      falsy when falsy in ["0", "false", false, nil] -> false
    end
  end
end
