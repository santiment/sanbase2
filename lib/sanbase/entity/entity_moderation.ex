defmodule Sanbase.Entity.Moderation do
  @moduledoc ~s"""

  """
  import Ecto.Query

  def set_deleted(entity_type, entity_id) do
    set_boolean_field(entity_type, entity_id, :is_deleted, true)
  end

  def set_hidden(entity_type, entity_id) do
    set_boolean_field(entity_type, entity_id, :is_hidden, true)
  end

  def set_featured(entity_type, entity_id) do
    with {:ok, entity} <- Sanbase.Entity.by_id(entity_type, entity_id),
         :ok <- Sanbase.FeaturedItem.update_item(entity, true) do
      {:ok, true}
    end
  end

  def unpublish_insight(insight_id) do
    case Sanbase.Insight.Post.unpublish(insight_id) do
      {:ok, _} -> {:ok, true}
      {:error, _} -> {:error, "Error unpublishing insight with id #{insight_id}"}
    end
  end

  defp set_boolean_field(entity_type, id, field, value)
       when field in [:is_deleted, :is_hidden] and is_boolean(value) do
    module = Sanbase.Entity.deduce_entity_module(entity_type)

    result =
      from(entity in module, where: entity.id == ^id)
      |> Sanbase.Repo.update_all(set: [{field, value}])

    case result do
      {1, nil} -> {:ok, true}
      _ -> {:error, "Error setting entity #{field} flag for entity #{entity_type} with id #{id}"}
    end
  end
end
