defmodule Sanbase.ExternalServices.ErrorCatcher.Middleware do
  @behaviour Tesla.Middleware

  def call(env, next, _opts) do
    try do
      Tesla.run(env, next)
    rescue
      e in Tesla.Error ->
        e

      # Raised on a corrupt or oversized gzip/deflate body; return it as a request error
      e in Tesla.Middleware.Compression.Error ->
        {:error, e}
    end
  end
end
