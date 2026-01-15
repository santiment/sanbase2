defmodule SanbaseWeb.Graphql.Resolvers.ProjectSignalsResolver do
  alias Sanbase.Project
  alias Sanbase.Signal

  def available_signals(%Project{slug: slug}, _args, _resolution) do
    Signal.available_signals(%{slug: slug})
  end
end
