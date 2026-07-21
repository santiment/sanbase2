defmodule Sanbase.LoadTest.DbGuard do
  @moduledoc """
  Safety guard for the `load_test.*` mix tasks, which insert/delete data.

  They must only ever run against a local database. `ensure_local_database!/0`
  raises before any data is touched when the environment points at a deployed
  database: `DATABASE_URL` set to a non-local host (e.g. an AWS RDS instance),
  a non-local `Sanbase.Repo` hostname, or `MIX_ENV=prod`.
  """

  @local_hosts ["localhost", "127.0.0.1", nil]

  @spec ensure_local_database!() :: :ok
  def ensure_local_database!() do
    database_url = System.get_env("DATABASE_URL")
    repo_hostname = Application.get_env(:sanbase, Sanbase.Repo, [])[:hostname]

    check_local!(
      env: Mix.env(),
      database_url: database_url,
      hosts: [url_host(database_url), resolve(repo_hostname)]
    )
  end

  @doc false
  def check_local!(opts) do
    env = Keyword.fetch!(opts, :env)
    database_url = Keyword.fetch!(opts, :database_url)
    hosts = Keyword.fetch!(opts, :hosts)

    cond do
      env == :prod ->
        refuse!("MIX_ENV is :prod")

      database_url && database_url =~ ~r/amazonaws|rds\.|\.aws\./i ->
        refuse!("DATABASE_URL points to AWS: #{scrub(database_url)}")

      Enum.any?(hosts, &(&1 not in @local_hosts)) ->
        refuse!("database host is not local: #{inspect(Enum.reject(hosts, &is_nil/1))}")

      true ->
        :ok
    end
  end

  defp url_host(nil), do: nil
  defp url_host(url), do: URI.parse(url).host

  defp resolve({:system, env_var, default}), do: System.get_env(env_var) || default
  defp resolve(other), do: other

  defp refuse!(reason) do
    raise """
    Refusing to run a load-test task against a non-local database: #{reason}.

    These tasks insert and delete data and must only run against localhost.
    """
  end

  defp scrub(url) do
    uri = URI.parse(url)
    "#{uri.scheme}://#{uri.host}:#{uri.port}/#{uri.path}"
  end
end
