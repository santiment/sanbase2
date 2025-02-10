defmodule SanbaseWeb.Presence do
  @moduledoc false
  use Phoenix.Presence,
    otp_app: :sanbase2,
    pubsub_server: Sanbase.PubSub
end
