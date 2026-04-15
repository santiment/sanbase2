defmodule Sanbase.RateLimit do
  use Hammer, backend: :ets
end
