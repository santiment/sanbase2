defmodule Sanbase.ExternalServices.RateLimiting.Server do
  @moduledoc false
  @module Application.compile_env(:sanbase, [__MODULE__, :implementation_module])

  defdelegate child_spec(name, options), to: @module
  defdelegate wait(name), to: @module
  defdelegate wait_until(name, until), to: @module
end
