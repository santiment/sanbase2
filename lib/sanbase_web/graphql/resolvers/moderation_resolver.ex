defmodule SanbaseWeb.Graphql.Resolvers.ModerationResolver do
  @moduledoc false
  alias Sanbase.Entity.Moderation

  def moderate_delete(_root, %{entity_type: type, entity_id: id, flag: flag}, %{context: %{is_moderator: true}}) do
    Moderation.set_deleted(type, id, flag)
  end

  def moderate_hide(_root, %{entity_type: type, entity_id: id, flag: flag}, %{context: %{is_moderator: true}}) do
    Moderation.set_hidden(type, id, flag)
  end

  def moderate_featured(_root, %{entity_type: type, entity_id: id, flag: flag}, %{context: %{is_moderator: true}}) do
    Moderation.set_featured(type, id, flag)
  end

  def unpublish_insight(_root, %{insight_id: insight_id}, %{context: %{is_moderator: true}}) do
    Moderation.unpublish_insight(insight_id)
  end
end
