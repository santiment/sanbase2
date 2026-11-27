defmodule Sanbase.ExternalServices.RateLimiting.PriorityMiddleware do
  @moduledoc ~s"""
  Tesla middleware for the `PriorityServer` rate limiter. The priority of a
  request is passed in the request opts, :normal by default:

      get(url, opts: [rate_limit_priority: :high])
  """
  @behaviour Tesla.Middleware

  alias Sanbase.ExternalServices.RateLimiting.PriorityServer

  @impl Tesla.Middleware
  def call(env, next, options) do
    priority = Keyword.get(env.opts, :rate_limit_priority, :normal)
    :ok = PriorityServer.wait(Keyword.fetch!(options, :name), priority)

    Tesla.run(env, next)
  end
end
