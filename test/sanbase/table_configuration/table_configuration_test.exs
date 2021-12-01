defmodule Sanbase.TableConfigurationTest do
  use Sanbase.DataCase, async: true

  import Sanbase.Factory

  test "deleting table config nullifies foreign key in watchlists" do
    config = insert(:table_configuration)
    watchlist = insert(:watchlist, table_configuration_id: config.id)

    assert Sanbase.UserList.by_id!(watchlist.id).table_configuration_id == config.id
    assert {:ok, _} = Sanbase.Repo.delete(config)
    assert Sanbase.UserList.by_id!(watchlist.id).table_configuration_id == nil
  end
end
