defmodule Sanbase.ExternalServices.RateLimiting.TestServer do
  @moduledoc false
  @behaviour Sanbase.ExternalServices.RateLimiting.Behavior

  use GenServer, restart: :permanent, shutdown: 5_000

  require Logger

  def child_spec(name, options \\ []) do
    %{
      id: name,
      start: {
        __MODULE__,
        :start_link,
        [Keyword.put(options, :name, name)]
      }
    }
  end

  def start_link(options) do
    GenServer.start_link(__MODULE__, nil, name: Keyword.get(options, :name))
  end

  def init(_) do
    {:ok, nil}
  end

  def wait(_) do
    :ok
  end

  def wait_until(_, _) do
    :ok
  end
end
