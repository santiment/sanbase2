defmodule Sanbase.LoadTest.DbGuardTest do
  use ExUnit.Case, async: true

  alias Sanbase.LoadTest.DbGuard

  test "allows localhost" do
    assert :ok ==
             DbGuard.check_local!(
               env: :dev,
               database_url: nil,
               hosts: ["localhost", nil]
             )

    assert :ok ==
             DbGuard.check_local!(
               env: :test,
               database_url: "ecto://user:pass@localhost:5432/db",
               hosts: ["localhost", "127.0.0.1"]
             )
  end

  test "refuses MIX_ENV=prod" do
    assert_raise RuntimeError, ~r/MIX_ENV is :prod/, fn ->
      DbGuard.check_local!(env: :prod, database_url: nil, hosts: ["localhost"])
    end
  end

  test "refuses DATABASE_URL pointing to AWS" do
    assert_raise RuntimeError, ~r/points to AWS/, fn ->
      DbGuard.check_local!(
        env: :dev,
        database_url: "ecto://user:secret@prod-db.abc123.eu-west-1.rds.amazonaws.com:5432/db",
        hosts: ["localhost"]
      )
    end
  end

  test "the AWS refusal message does not leak credentials" do
    error =
      assert_raise RuntimeError, fn ->
        DbGuard.check_local!(
          env: :dev,
          database_url: "ecto://user:supersecret@db.rds.amazonaws.com:5432/db",
          hosts: ["localhost"]
        )
      end

    refute error.message =~ "supersecret"
  end

  test "every load_test mix task runs behind the migrations' database_safety alias" do
    aliases = Mix.Project.config()[:aliases]

    for task <- ["load_test.setup", "load_test.seed_projects", "load_test.cleanup"] do
      assert Keyword.get(aliases, String.to_atom(task)) ==
               ["load_dotenv", "database_safety", task],
             "#{task} must be aliased to run load_dotenv and database_safety first"
    end
  end

  test "refuses non-local database hosts" do
    assert_raise RuntimeError, ~r/not local/, fn ->
      DbGuard.check_local!(
        env: :dev,
        database_url: nil,
        hosts: ["stage-db.santiment.net", "localhost"]
      )
    end
  end
end
