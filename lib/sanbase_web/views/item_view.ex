defmodule SanbaseWeb.ItemView do
  use SanbaseWeb, :view

  def render("index.json", %{items: items}) do
    %{
      items: items
    }
  end
end
