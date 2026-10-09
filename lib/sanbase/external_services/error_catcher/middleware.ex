defmodule Sanbase.ExternalServices.ErrorCatcher.Middleware do
  @behaviour Tesla.Middleware

  def call(env, next, _opts) do
    try do
      Tesla.run(env, next)
    rescue
      e in Tesla.Error ->
        e

      # A truncated or invalid gzip/deflate body (or one over :max_body_size)
      # makes Tesla.Middleware.Compression raise. Return it as a regular
      # request error so callers handle it like any other failed request.
      e in Tesla.Middleware.Compression.Error ->
        {:error, e}
    end
  end
end
