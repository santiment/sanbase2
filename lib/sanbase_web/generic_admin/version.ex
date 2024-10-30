defmodule SanbaseWeb.GenericAdmin.Version do
  import Ecto.Query
  def schema_module, do: Sanbase.Version

  def resource() do
    %{
      actions: [:show],
      preloads: [:user],
      index_fields: [
        :id,
        :entity_id,
        :entity_schema,
        :action,
        :recorded_at,
        :rollback
      ],
      fields_override: %{
        patch: %{
          value_modifier: &format_patch/1
        }
      }
    }
  end

  defp format_patch(%{patch: patch}) when is_map(patch) do
    patch
    |> Enum.map_join("\n", fn {field, change} ->
      format_change(field, change)
    end)
  end

  defp format_patch(_), do: ""

  defp format_change(field, {:changed, {:primitive_change, old_val, new_val}}) do
    "#{field}: #{inspect(old_val)} → #{inspect(new_val)}"
  end

  defp format_change(field, {:changed, nested}) when is_map(nested) do
    nested_changes =
      nested
      |> Enum.map_join(", ", fn {k, v} -> format_change(k, v) end)

    "#{field}: {#{nested_changes}}"
  end

  defp format_change(field, other), do: "#{field}: #{inspect(other)}"
end
