defmodule Sanbase.ExternalServices.ErrorCatcher.Middleware do
  @behaviour Tesla.Middleware

  def call(env, next, _opts) do
    try do
      Tesla.run(env, next)
    rescue
      e in Tesla.Error -> e
    end
  end
end
