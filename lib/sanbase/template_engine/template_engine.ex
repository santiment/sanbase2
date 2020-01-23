defmodule Sanbase.TemplateEngine do
  @moduledoc ~s"""
  """

  def run(template, kv) do
    Enum.reduce(kv, template, fn {key, value}, acc ->
      String.replace(acc, "{{#{key}}}", fn _ -> value |> to_string() end)
    end)
  end
end
