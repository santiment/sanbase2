defmodule SanbaseWeb.ErrorView do
  use SanbaseWeb, :view

  def render("404.json", assigns) do
    IO.inspect(assigns)

    IO.inspect(
      label:
        "404 #{String.replace_leading("#{__ENV__.file}", "#{File.cwd!()}", "") |> Path.relative()}:#{
          __ENV__.line()
        }"
    )

    Process.sleep(10_000_000)

    %{errors: %{details: "Page not found"}}
  end

  def render("500.json", assigns) do
    IO.inspect(assigns)

    IO.inspect(
      label:
        "500 #{String.replace_leading("#{__ENV__.file}", "#{File.cwd!()}", "") |> Path.relative()}:#{
          __ENV__.line()
        }"
    )

    Process.sleep(10_000_000)

    %{errors: %{details: "Internal server error"}}
  end

  # In case no render clause matches or no
  # template is found, let's render it as 500
  def template_not_found(template, assigns) do
    IO.inspect({template, assigns})

    IO.inspect(
      label:
        "TEMPLATE NOT FOUND #{
          String.replace_leading("#{__ENV__.file}", "#{File.cwd!()}", "") |> Path.relative()
        }:#{__ENV__.line()}"
    )

    Process.sleep(10_000_000)

    render("500.json", assigns)
  end
end
