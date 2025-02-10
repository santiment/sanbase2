defmodule Sanbase.ExternalServices.RateLimiting.Behavior do
  @moduledoc false
  @callback child_spec(name :: atom, options :: list()) :: %{
              required(:id) => atom(),
              required(:start) => {atom(), atom(), list()}
            }

  @callback wait(name :: atom()) :: :ok
  @callback wait_until(name :: atom(), datetime :: DateTime.t()) :: :ok
end
