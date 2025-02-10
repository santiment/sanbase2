defmodule SanbaseWeb.Graphql.Resolvers.ProjectSignalsResolver do
  @moduledoc false
  alias Sanbase.Project
  alias Sanbase.Signal

  require Logger

  def available_signals(%Project{slug: slug}, _args, _resolution) do
    Signal.available_signals(%{slug: slug})
  end
end
