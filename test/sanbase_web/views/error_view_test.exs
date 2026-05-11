defmodule SanbaseWeb.ErrorJSONTest do
  use SanbaseWeb.ConnCase, async: true

  test "renders 400.json" do
    assert SanbaseWeb.ErrorJSON.render("400.json", []) == %{errors: %{details: "Bad request"}}
  end

  test "renders 404.json" do
    assert SanbaseWeb.ErrorJSON.render("404.json", []) ==
             %{errors: %{details: "Page not found"}}
  end

  test "render 500.json" do
    assert SanbaseWeb.ErrorJSON.render("500.json", []) ==
             %{errors: %{details: "Internal server error"}}
  end

  test "render any other status" do
    assert SanbaseWeb.ErrorJSON.render("503.json", []) ==
             %{errors: %{details: "Service Unavailable"}}
  end
end
