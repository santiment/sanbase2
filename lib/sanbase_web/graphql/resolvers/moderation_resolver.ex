defmodule SanbaseWeb.Graphql.Resolvers.ModerationResolver do
  def moderate_delete(_root, %{entity_type: type, entity_id: id}, _resolution) do
    Sanbase.Entity.Moderation.set_deleted(type, id)
  end

  def moderate_hide(_root, %{entity_type: type, entity_id: id}, _resolution) do
    Sanbase.Entity.Moderation.set_hidden(type, id)
  end

  def unpublish_insight(_root, %{insight_id: insight_id}, _resolution) do
    Sanbase.Entity.Moderation.unpublish_insight(insight_id)
  end
end
