defmodule Sanbase.Application.Admin do
  @moduledoc ~s"""
  The Admin pod is used to interact with the admin dashboard.
  A separate pod is required so the access to it can be better secured compared
  to when the admin dashboard was part of the web pod
  """
  require Logger

  def init() do
    :ok
  end

  @doc ~s"""
  Return the children and options that will be started in the admin container.
  Along with these children all children from `Sanbase.Application.common_children/0`
  will be started, too.
  """
  def children() do
    # Define workers and child supervisors to be supervised
    children = []

    opts = [
      name: Sanbase.WebSupervisor,
      strategy: :one_for_one,
      max_restarts: 5,
      max_seconds: 1
    ]

    {children, opts}
  end
end
