defmodule SanbaseWeb.Graphql.TrackEventsResolverTest do
  use Sanbase.DataCase, async: true

  alias SanbaseWeb.Graphql.Resolvers.IntercomResolver

  test "a call without events returns an error instead of raising" do
    resolution = %Absinthe.Resolution{context: %{}}

    assert {:error, "The list of events contains invalid event(s)"} =
             IntercomResolver.track_events(
               %{},
               %{anonymous_user_id: String.duplicate("a", 28)},
               resolution
             )
  end
end
