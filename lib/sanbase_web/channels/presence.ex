defmodule SanbaseWeb.Presence do
  use Phoenix.Presence,
    otp_app: :sanbase2,
    pubsub_server: Sanbase.PubSub
end
