defmodule Sanbase.ExAdmin.Statistics do
  use ExAdmin.Register

  register_page "Statistics" do
    menu(priority: 1, label: "Statistics")

    content do
      h2 do
        div("Sanbase statistics.")
      end

      Sanbase.Statistics.get_all()
      |> Enum.map(fn {name, map} ->
        table do
          h3("#{format_underscored(name)}")

          Enum.map(map, fn {key, value} ->
            tr do
              td("#{format_underscored(key)}")

              td do
                pre("|", style: "all: initial; margin: 0 10px 0 10px;")
              end

              td("#{value}")
            end
          end)
        end
      end)
    end
  end

  defp format_underscored(key) when is_binary(key) do
    key
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
