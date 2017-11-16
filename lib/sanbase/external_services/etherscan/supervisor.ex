defmodule Sanbase.ExternalServices.Etherscan.Supervisor do
  use Supervisor

  alias Sanbase.ExternalServices.Etherscan.{RateLimiter, Worker}

  def start_link(_) do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    children = [
      RateLimiter,
      Worker,
      {Task.Supervisor, [name: Sanbase.ExternalServices.Etherscan.TaskSupervisor]}
    ]
    Supervisor.init(children, strategy: :rest_for_one)
  end
end
