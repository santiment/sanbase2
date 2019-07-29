defmodule Sanbase.ExternalServices.RateLimiting.Server do
  require Sanbase.Utils.Config, as: Config
  @module Config.get(:implementation_module)

  defdelegate child_spec(name, options), to: @module
  defdelegate wait(name), to: @module
  defdelegate wait_until(name, until), to: @module
end
