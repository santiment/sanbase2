defmodule SanbaseWeb.Graphql.Resolvers.FreeFormJsonStorageResolver do
  require Logger

  def get_json(_root, %{key: key}, _resolution) do
    Sanbase.FreeFormJsonStorage.get(key)
  end

  def create_json(_root, %{key: key, value: value}, _resolution) do
    Sanbase.FreeFormJsonStorage.create(key, value)
  end

  def update_json(_root, %{key: key, value: value}, _resolution) do
    Sanbase.FreeFormJsonStorage.update(key, value)
  end

  def delete_json(_root, %{key: key}, _resolution) do
    Sanbase.FreeFormJsonStorage.delete(key)
  end
end
