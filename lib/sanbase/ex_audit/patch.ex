defmodule Sanbase.ExAudit.Patch do
  def format_patch(%{patch: patch}) when is_map(patch) do
    changes =
      patch
      |> Enum.map(fn {field, change} ->
        safe_field = Phoenix.HTML.html_escape(to_string(field))
        safe_change = Phoenix.HTML.html_escape(format_change_value(change))

        content = PhoenixHTMLHelpers.Tag.content_tag(:strong, safe_field)
        PhoenixHTMLHelpers.Tag.content_tag(:li, [content, ": ", safe_change])
      end)

    PhoenixHTMLHelpers.Tag.content_tag(:ul, changes, class: "list-disc list-inside")
  end

  def format_patch(_), do: Phoenix.HTML.raw("")

  defp format_change_value({:changed, {:primitive_change, old_val, new_val}}) do
    old = inspect(old_val)
    new = inspect(new_val)
    "#{old} → #{new}"
  end

  defp format_change_value({:changed, nested}) when is_map(nested) do
    nested_changes =
      nested
      |> Enum.map_join(", ", fn {k, v} ->
        "#{to_string(k)}: #{format_change_value(v)}"
      end)

    "{#{nested_changes}}"
  end

  defp format_change_value(other), do: inspect(other)
end
