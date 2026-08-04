defmodule Sanbase.Logger.ActivityTracesFilterWatchdog do
  @moduledoc """
  Re-installs the `Sanbase.Logger.MaybeHideActivityTraces` primary filter
  after OTP drops it.

  `:logger` removes a primary filter permanently the first time it
  raises, leaving protected users' queries unredacted until the node
  restarts. The filter's own `catch` cannot cover its module being
  unloaded (code purge, hot upgrade) — the `:undef` fires before the
  `catch` is entered — so this watchdog polls and re-installs, logging
  at `:error` so the redaction gap is visible in Sentry.
  """

  use GenServer

  require Logger

  alias Sanbase.Logger.MaybeHideActivityTraces

  # Inlined at compile time so detection never calls the module whose
  # absence it detects.
  @filter_id MaybeHideActivityTraces.filter_id()

  @default_check_interval :timer.seconds(30)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    check_interval = Keyword.get(opts, :check_interval, @default_check_interval)

    if not (is_integer(check_interval) and check_interval > 0) do
      raise ArgumentError,
            ":check_interval must be a positive integer, got: #{inspect(check_interval)}"
    end

    # Interval, not a re-arming send_after — see Sanbase.KafkaExporter.init/1.
    {:ok, _tref} = :timer.send_interval(check_interval, :check)

    {:ok, %{check_interval: check_interval}}
  end

  @doc """
  Run a check synchronously.
  """
  @spec check_now() :: :ok
  def check_now(), do: GenServer.call(__MODULE__, :check_now)

  @impl true
  def handle_call(:check_now, _from, state) do
    check_and_reinstall(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:check, state) do
    check_and_reinstall(state)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # Reads the config directly — detection must work while
  # MaybeHideActivityTraces is unloaded.
  defp check_and_reinstall(state) do
    %{filters: filters} = :logger.get_primary_config()

    if not List.keymember?(filters, @filter_id, 0) do
      reinstall(state)
    end

    :ok
  end

  defp reinstall(state) do
    MaybeHideActivityTraces.install!()

    Logger.error(
      "[ActivityTracesFilterWatchdog] The #{inspect(@filter_id)} logger filter was missing " <>
        "and has been re-installed. Redaction was disabled since the preceding " <>
        "{removed_failing_filter, #{inspect(@filter_id)}} error."
    )
  rescue
    error ->
      # Likely the filter module is mid-purge; retry on the next tick.
      Logger.error(
        "[ActivityTracesFilterWatchdog] Failed to re-install the #{inspect(@filter_id)} " <>
          "logger filter, retrying in #{state.check_interval}ms: #{Exception.message(error)}"
      )
  end
end
