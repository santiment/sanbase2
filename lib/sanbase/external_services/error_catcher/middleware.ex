defmodule Sanbase.ExternalServices.ErrorCatcher.Middleware do
  @moduledoc false
  @behaviour Tesla.Middleware

  def call(env, next, _opts) do
    Tesla.run(env, next)
  rescue
    e in Tesla.Error -> e
  end
end
