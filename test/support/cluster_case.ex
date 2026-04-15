defmodule Sanbase.ClusterCase do
  @moduledoc """
  Helpers for tests that need a second BEAM node.

  Typical use: simulate cross-pod delivery of `SanbaseWeb.Endpoint.broadcast/3`
  through distributed `Phoenix.PubSub` (`:pg` adapter). The primary test node
  plays the role of the `web` pod (channels live here); a peer node plays the
  role of the `signals`/`alerts` pod that originates the broadcast.

  Tag tests with `@moduletag :distributed` so they can be filtered on demand
  (e.g. `mix test --exclude distributed` for a fast local run). By default
  these tests run as part of the normal suite — both locally and in CI —
  because `ensure_distributed!/0` below self-bootstraps EPMD and the test
  node.
  """

  @cookie :sanbase_test_cookie

  @doc """
  Starts a peer BEAM node connected to the current node and returns
  `{peer, node_name}`.

  Supported modes:

    * `:pubsub_only` - starts only `Phoenix.PubSub` on the peer.
    * `{:sanbase, container_type}` - boots the real `:sanbase` application on
      the peer under the given container type (`"web"`, `"signals"`, etc.).

  In `{:sanbase, container_type}` mode the peer endpoint listens on port `0`
  so the test node and peer node can run concurrently without port clashes.
  """
  @spec start_peer!(atom() | String.t(), keyword()) :: {pid(), node()}
  def start_peer!(name_prefix, opts \\ []) do
    ensure_distributed!()

    peer_name = :"#{name_prefix}-#{System.unique_integer([:positive])}"

    {:ok, peer, node} =
      :peer.start_link(%{
        name: peer_name,
        host: ~c"127.0.0.1",
        longnames: true,
        args: [~c"-setcookie", Atom.to_charlist(@cookie)]
      })

    try do
      # Let the peer load our app + deps modules
      :ok = :erpc.call(node, :code, :add_paths, [:code.get_path()])

      case Keyword.get(opts, :mode, :pubsub_only) do
        :pubsub_only ->
          start_peer_pubsub!(node)

        {:sanbase, container_type} when is_binary(container_type) ->
          start_peer_sanbase!(node, container_type)

        mode ->
          raise ArgumentError, "Unsupported peer mode: #{inspect(mode)}"
      end

      {peer, node}
    rescue
      exception ->
        if Process.alive?(peer), do: :peer.stop(peer)
        reraise exception, __STACKTRACE__
    catch
      kind, reason ->
        if Process.alive?(peer), do: :peer.stop(peer)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp start_peer_pubsub!(node) do
    # Start Phoenix.PubSub on the peer with the same name the web node uses.
    # That is enough to share the distributed PubSub scope with the primary.
    #
    # We spawn a long-lived holder process on the peer to own the link from
    # `Phoenix.PubSub.Supervisor.start_link/1`. Otherwise the supervisor
    # dies together with the ephemeral erpc handler process.
    {:ok, _} = :erpc.call(node, :application, :ensure_all_started, [:phoenix_pubsub])
    _holder = :erpc.call(node, :erlang, :spawn, [&__MODULE__.peer_pubsub_loop/0])

    wait_until!(
      fn -> is_pid(:erpc.call(node, Process, :whereis, [Sanbase.PubSub])) end,
      "Timed out waiting for Sanbase.PubSub on peer #{node}"
    )
  end

  defp start_peer_sanbase!(node, container_type) do
    # Set CONTAINER_TYPE on the peer *before* copying application env so any
    # runtime config lookups that read it (System.get_env/1 and friends) see
    # the peer's intended container type rather than the primary's.
    :ok = :erpc.call(node, System, :put_env, ["CONTAINER_TYPE", container_type])

    copy_application_envs!(node)

    endpoint_config =
      Application.fetch_env!(:sanbase, SanbaseWeb.Endpoint)
      |> Keyword.put(:server, true)
      |> Keyword.update(:http, [port: 0], &Keyword.put(&1, :port, 0))

    :ok =
      :erpc.call(node, Application, :put_env, [
        :sanbase,
        SanbaseWeb.Endpoint,
        endpoint_config,
        [persistent: true]
      ])

    {:ok, _} = :erpc.call(node, :application, :ensure_all_started, [:sanbase])

    wait_until!(
      fn -> is_pid(:erpc.call(node, Process, :whereis, [Sanbase.PubSub])) end,
      "Timed out waiting for Sanbase.PubSub on peer #{node}"
    )
  end

  defp copy_application_envs!(node) do
    envs =
      Application.loaded_applications()
      |> Enum.flat_map(fn {app, _description, _version} ->
        for {key, value} <- Application.get_all_env(app), do: {app, key, value}
      end)

    :ok = :erpc.call(node, __MODULE__, :put_application_envs, [envs])
  end

  @doc false
  @spec put_application_envs([{atom(), atom(), term()}]) :: :ok
  def put_application_envs(envs) do
    Enum.each(envs, fn {app, key, value} ->
      Application.put_env(app, key, value, persistent: true)
    end)

    :ok
  end

  @doc false
  # Runs on the peer. Starts Phoenix.PubSub under a link owned by this
  # process, then sleeps forever so the link (and the supervisor) survives
  # for the lifetime of the peer node.
  @spec peer_pubsub_loop() :: :ok
  def peer_pubsub_loop do
    {:ok, _pid} = Phoenix.PubSub.Supervisor.start_link(name: Sanbase.PubSub)
    Process.flag(:trap_exit, true)

    receive do
      :stop -> :ok
    end
  end

  @doc """
  Subscribes `self()` to `topic` on `pubsub` and forwards every received
  message to `target_pid`, tagged with `ref`. Also sends
  `{ref, :subscribed}` once the subscription is in place, so the caller
  can wait for it deterministically.

  Designed to be spawned on a peer node via
  `:erlang.spawn(Sanbase.ClusterCase, :subscribe_and_forward, [...])`.
  """
  @spec subscribe_and_forward(atom(), String.t(), pid(), reference()) :: no_return()
  def subscribe_and_forward(pubsub, topic, target_pid, ref) do
    :ok = Phoenix.PubSub.subscribe(pubsub, topic)
    send(target_pid, {ref, :subscribed})
    forward_loop(target_pid, ref)
  end

  defp forward_loop(target_pid, ref) do
    receive do
      msg ->
        send(target_pid, {ref, msg})
        forward_loop(target_pid, ref)
    end
  end

  @doc "Stop a peer previously started via `start_peer!/1`."
  @spec stop_peer(pid()) :: :ok
  def stop_peer(peer), do: :peer.stop(peer)

  @doc """
  Polls `fun` until it returns a truthy value or `timeout_ms` elapses.
  Returns `:ok` on success, `{:error, :timeout}` otherwise.
  """
  @spec wait_until((-> boolean()), non_neg_integer(), non_neg_integer()) ::
          :ok | {:error, :timeout}
  def wait_until(fun, timeout_ms \\ 2_000, interval_ms \\ 50) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_until(fun, deadline, interval_ms)
  end

  @spec wait_until!((-> boolean()), String.t(), non_neg_integer(), non_neg_integer()) :: :ok
  def wait_until!(fun, error_message, timeout_ms \\ 2_000, interval_ms \\ 50) do
    case wait_until(fun, timeout_ms, interval_ms) do
      :ok -> :ok
      {:error, :timeout} -> raise error_message
    end
  end

  defp do_wait_until(fun, deadline, interval_ms) do
    if fun.() do
      :ok
    else
      if System.monotonic_time(:millisecond) >= deadline do
        {:error, :timeout}
      else
        Process.sleep(interval_ms)
        do_wait_until(fun, deadline, interval_ms)
      end
    end
  end

  defp ensure_distributed! do
    unless Node.alive?() do
      # EPMD is not started automatically when `mix test` runs without a
      # `--name`/`--sname` kernel flag (the common case in CI containers
      # that just execute `mix test`). `:net_kernel.start/1` will fail with
      # `:nodistribution` if EPMD isn't reachable, so spawn it explicitly
      # before trying to bring the distribution stack up.
      _ = :os.cmd(~c"epmd -daemon")

      case :net_kernel.start([primary_name(), :longnames]) do
        {:ok, _} ->
          :ok

        {:error, {:already_started, _}} ->
          :ok

        {:error, reason} ->
          raise """
          Failed to start the distributed Erlang runtime for cluster tests.

          `:net_kernel.start/1` returned: #{inspect(reason)}

          This usually means EPMD could not be launched in the current
          environment (e.g. a minimal CI container). Make sure the `epmd`
          binary is available on PATH, or run the test with a pre-started
          node via `elixir --name test@127.0.0.1 -S mix test ...`.
          """
      end
    end

    Node.set_cookie(@cookie)
    :ok
  end

  defp primary_name do
    partition = System.get_env("MIX_TEST_PARTITION", "0")
    unique = System.unique_integer([:positive])

    :"primary-#{partition}-#{unique}@127.0.0.1"
  end
end
