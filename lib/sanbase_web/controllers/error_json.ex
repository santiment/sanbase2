defmodule SanbaseWeb.ErrorJSON do
  def render("400.json", _assigns) do
    %{errors: %{details: "Bad request"}}
  end

  def render("404.json", _assigns) do
    %{errors: %{details: "Page not found"}}
  end

  def render("500.json", _assigns) do
    %{errors: %{details: "Internal server error"}}
  end

  def render(template, _assigns) do
    %{errors: %{details: Phoenix.Controller.status_message_from_template(template)}}
  end
end
