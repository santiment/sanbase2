defmodule SanbaseWeb.GenericAdminController.LinkBuilder do
  @moduledoc """
  Builds HTML links for belongs_to associations on a record.

  Given an Ecto schema module and a record, introspects the schema's
  associations and generates clickable links to the related GenericAdmin
  show pages. Used by the index and show views to render foreign key
  fields as navigable links instead of raw IDs.
  """

  @doc """
  Returns a map of `{field_name, link}` pairs for all belongs_to
  associations on the given record.
  """
  def build_link(module, record) do
    module.__schema__(:associations)
    |> Enum.reduce(%{}, fn assoc_name, acc ->
      assoc_info = module.__schema__(:association, assoc_name)

      case assoc_info do
        %Ecto.Association.BelongsTo{related: related_module} ->
          {field, link} = link_belongs_to(record, related_module, assoc_name)
          Map.put(acc, field, link)

        _ ->
          acc
      end
    end)
  end

  defp link_belongs_to(record, related_module, assoc_name) do
    # credo:disable-for-next-line
    field_name = String.to_atom("#{assoc_name}_id")
    field_value = Map.get(record, field_name)

    cond do
      is_nil(field_value) ->
        {to_string(assoc_name), nil}

      resource = module_to_resource_name(related_module) ->
        link = href(resource, field_value, "#{field_name}: #{field_value}")
        {field_name, link}

      true ->
        # No admin module registered for this schema — show plain text
        {field_name, "#{field_name}: #{field_value}"}
    end
  end

  defp href(resource, id, label) do
    SanbaseWeb.GenericAdmin.resource_link(resource, id, label)
  end

  defp module_to_resource_name(module) do
    SanbaseWeb.GenericAdmin.resource_module_map()
    |> Enum.find_value(fn {resource_name, config} ->
      if config[:module] == module, do: resource_name
    end)
  end
end
