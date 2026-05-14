defmodule Sanbase.Application.ObanSupervisor do
  @moduledoc """
  Wraps an Oban instance so the host application supervisor is shielded from
  transient `Oban.Sonar` crashes.

  In dev, Mix recompiles run in the background while the app is already up.
  Loading a freshly compiled `.beam` briefly purges the previous version of
  the module. If `Oban.Sonar` ticks during that window, `Sanbase.Repo.query/3`
  is reported as undefined and Sonar crashes. Under the host supervisor's
  tight `max_restarts: 5, max_seconds: 1` policy, that single crash can
  cascade and shut down the whole app. This dedicated supervisor isolates
  those restarts behind a more forgiving policy and pre-loads `Sanbase.Repo`
  to narrow the window.
  """
  use Supervisor

  alias Sanbase.Utils.Config

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    config = Keyword.fetch!(opts, :config)
    oban_name = Keyword.fetch!(config, :name)

    %{
      id: {__MODULE__, oban_name},
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  def start_link(opts) do
    config = Keyword.fetch!(opts, :config)
    oban_name = Keyword.fetch!(config, :name)
    sup_name = Module.concat(__MODULE__, oban_name)

    Supervisor.start_link(__MODULE__, config, name: sup_name)
  end

  @impl true
  def init(config) do
    Code.ensure_loaded!(Sanbase.Repo)

    children = [{Oban, config}]

    Supervisor.init(children, strategy: :one_for_one, max_restarts: 10, max_seconds: 60)
  end

  @doc """
  Whether Oban should be started in the current environment.

  In `:dev`, Oban is opt-in via `OBAN_ENABLED=true` so the dev recompile
  race is avoided entirely unless the developer is actively working on
  Oban-driven flows. In all other envs Oban always starts.
  """
  @spec enabled?() :: boolean()
  def enabled?() do
    case Config.module_get(Sanbase, :env) do
      :dev ->
        System.get_env("OBAN_ENABLED", "false")
        |> to_string()
        |> String.trim()
        |> String.downcase()
        |> Kernel.in(["true", "1"])

      _ ->
        true
    end
  end
end
