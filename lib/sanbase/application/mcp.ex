defmodule Sanbase.Application.Mcp do
  import Sanbase.ApplicationUtils

  def init() do
    :ok
  end

  def children() do
    children = []

    opts = [
      name: Sanbase.McpSupervisor,
      strategy: :one_for_one,
      max_restarts: 5,
      max_seconds: 1
    ]

    {children, opts}
  end
end
