defmodule SanbaseWeb.Graphql.Resolvers.EcosystemResolver do
  def get_ecosystems(_root, _args, _resolution) do
    Sanbase.Ecosystem.get_ecosystems_with_projects()
  end
end
