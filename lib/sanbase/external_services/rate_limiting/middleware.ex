defmodule Sanbase.ExternalServices.RateLimiting.Middleware do
  @behaviour Tesla.Middleware

  alias Sanbase.ExternalServices.RateLimiting.Server

  def call(env, next, options) do
    Server.wait(Keyword.get(options, :name))

    Tesla.run(env, next)
  end
end
