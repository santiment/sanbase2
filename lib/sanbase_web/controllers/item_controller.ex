defmodule SanbaseWeb.ItemController do
  use SanbaseWeb, :controller
  alias Sanbase.{Item, Repo}

  def index(conn, _params) do
    item_names = Repo.all(Item)
    |> Enum.map(&(&1.name))

    render conn, "index.json", items: item_names
  end
end
