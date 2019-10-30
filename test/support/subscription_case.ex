defmodule SanbaseWeb.SubscriptionCase do
  @moduledoc """
  This module defines the test case to be used by
  subscription tests
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with channels
      use SanbaseWeb.ChannelCase

      use Absinthe.Phoenix.SubscriptionTest,
        schema: SanbaseWeb.Graphql.Schema

      setup do
        {:ok, socket} = Phoenix.ChannelTest.connect(SanbaseWeb.UserSocket, %{})
        {:ok, socket} = Absinthe.Phoenix.SubscriptionTest.join_absinthe(socket)

        {:ok, socket: socket}
      end
    end
  end
end
