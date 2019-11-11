defmodule Sanbase.Clickhouse.Metric.LabelTemplate do
  def get(values, template) do
    values
    |> List.wrap()
    |> Enum.with_index(1)
    |> Enum.reduce(template, fn {elem, index}, acc ->
      String.replace(acc, "${#{index}}", fn _ -> elem |> to_string end)
    end)
  end
end
