defmodule Sanbase.MCP.Registry.PgTest do
  use ExUnit.Case, async: true

  alias Sanbase.MCP.Registry.Pg

  @registry_name :"test.registry.#{System.unique_integer([:positive])}"

  setup do
    # Start a dedicated :pg scope for test isolation
    scope = :"test_pg_#{System.unique_integer([:positive])}"

    start_supervised!(%{
      id: {:pg, scope},
      start: {:pg, :start_link, [scope]}
    })

    # Temporarily override the scope for testing by using the real scope
    # Since the module uses a compile-time constant, we test via the real scope
    # that is started in the application supervision tree.
    # For unit tests, we test the behaviour contract directly.
    {:ok, scope: scope}
  end

  describe "child_spec/1" do
    test "returns :ignore since :pg scope is started externally" do
      assert :ignore = Pg.child_spec([])
    end
  end

  describe "register_session/3 and lookup_session/2" do
    test "registers and looks up a session" do
      assert {:error, :not_found} = Pg.lookup_session(@registry_name, "sess-1")

      assert :ok = Pg.register_session(@registry_name, "sess-1", self())
      assert {:ok, pid} = Pg.lookup_session(@registry_name, "sess-1")
      assert pid == self()
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = Pg.lookup_session(@registry_name, "nonexistent")
    end
  end

  describe "unregister_session/2" do
    test "removes a session" do
      :ok = Pg.register_session(@registry_name, "sess-2", self())
      assert {:ok, _} = Pg.lookup_session(@registry_name, "sess-2")

      :ok = Pg.unregister_session(@registry_name, "sess-2")
      assert {:error, :not_found} = Pg.lookup_session(@registry_name, "sess-2")
    end

    test "is a no-op for unknown session" do
      assert :ok = Pg.unregister_session(@registry_name, "nonexistent")
    end
  end

  describe "automatic cleanup on process exit" do
    test "session is removed when the owning process exits" do
      {pid, ref} =
        spawn_monitor(fn ->
          receive do
            :stop -> :ok
          end
        end)

      :ok = Pg.register_session(@registry_name, "sess-3", pid)
      assert {:ok, ^pid} = Pg.lookup_session(@registry_name, "sess-3")

      send(pid, :stop)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

      # :pg cleanup is async — give it a moment
      Process.sleep(50)
      assert {:error, :not_found} = Pg.lookup_session(@registry_name, "sess-3")
    end
  end
end
