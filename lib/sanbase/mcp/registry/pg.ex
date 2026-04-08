defmodule Sanbase.MCP.Registry.Pg do
  @moduledoc """
  Distributed MCP session registry backed by Erlang's `:pg` process groups.

  Uses `:pg` to register session PIDs in named groups that are automatically
  synchronized across all connected BEAM nodes (via libcluster). Any pod can
  look up a session PID regardless of which pod owns it, and the caller can
  then make a remote `GenServer.call` to that PID through distributed Erlang.

  The `:pg` scope (`:sanbase_mcp_sessions`) must be started in the application
  supervision tree before any MCP servers — see `Sanbase.Application.Mcp`.

  Automatic cleanup: `:pg` removes a PID from all its groups when the process
  exits, so no explicit cleanup is needed on session timeout or pod shutdown.
  """

  @behaviour Anubis.Server.Registry

  @scope :sanbase_mcp_sessions

  @doc "Returns the `:pg` scope atom used by this registry."
  def scope, do: @scope

  # The :pg scope is started in Sanbase.Application.Mcp, not here.
  @impl Anubis.Server.Registry
  def child_spec(_opts), do: :ignore

  @impl Anubis.Server.Registry
  def register_session(name, session_id, pid) do
    :pg.join(@scope, {name, session_id}, pid)
  end

  @impl Anubis.Server.Registry
  def lookup_session(name, session_id) do
    case :pg.get_members(@scope, {name, session_id}) do
      [pid | _] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @impl Anubis.Server.Registry
  def unregister_session(name, session_id) do
    for pid <- :pg.get_members(@scope, {name, session_id}) do
      :pg.leave(@scope, {name, session_id}, pid)
    end

    :ok
  end
end
