defmodule Integartion.HomeTest do
  use Sanbase.IntegrationCase, async: false

  alias Sanbase.Item
  alias Sanbase.Repo

  test "viewing the list of items and navigating to the about page" do
    %Item{name: "Milk"} |> Repo.insert

    navigate_to("http://localhost:3001/")

    assert find_element(:tag, "h1") |> inner_text == "Welcome to NextJS!"

    assert find_element(:class, "todo_list") |> inner_text |> String.trim == "Milk"

    click({:id, "about"})

    content = find_element(:class, "content")

    assert content |> visible_text() =~ "This is a simple phoenix app"
  end
end
