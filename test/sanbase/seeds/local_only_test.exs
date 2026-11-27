defmodule Sanbase.Seeds.LocalOnlyTest do
  use ExUnit.Case, async: true

  alias Sanbase.Seeds.LocalOnly

  @stage_url "ecto://user:pass@postgres-rds-stage.abc.eu-central-1.rds.amazonaws.com:5432/santiment"

  test "allows a local database" do
    assert :ok = LocalOnly.check(nil, "localhost", :dev)
    assert :ok = LocalOnly.check("", "127.0.0.1", :dev)
    assert :ok = LocalOnly.check("ecto://postgres:postgres@localhost/sanbase_dev", nil, :dev)
  end

  test "DATABASE_URL wins over the Repo hostname" do
    assert {:error, _} = LocalOnly.check(@stage_url, "localhost", :dev)
    assert :ok = LocalOnly.check("ecto://postgres@localhost/sanbase_dev", "db.example.com", :dev)
  end

  test "rejects remote databases and the prod environment" do
    assert {:error, _} = LocalOnly.check(nil, "postgres-rds-production.amazonaws.com", :dev)
    assert {:error, _} = LocalOnly.check(nil, "localhost.evil.com", :dev)
    assert {:error, _} = LocalOnly.check(nil, nil, :dev)
    assert {:error, _} = LocalOnly.check(nil, "localhost", :prod)
  end
end
