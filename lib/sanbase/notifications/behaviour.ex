defmodule Sanbase.Notifications.Behaviour do
  @typedoc ~s"""
  String describing the place where the notification is published.
  Currently we have implementations for "discord" and "discourse"
  """
  @type publish_place :: String.t()

  @type payload :: any

  @callback run :: :ok | {:error, String.t()}
  @callback publish(payload, publish_place) :: :ok | {:error, String.t()}
end
