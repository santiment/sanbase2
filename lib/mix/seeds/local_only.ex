defmodule Sanbase.Seeds.LocalOnly do
  @moduledoc """
  Seed scripts write made-up data, so they run only against a database on this
  machine. Call `ensure!/0` before a seed script touches the database.
  """

  @local_hosts ["localhost", "127.0.0.1", "::1"]

  @spec ensure!() :: :ok
  def ensure!() do
    case check(
           System.get_env("DATABASE_URL"),
           Sanbase.Utils.Config.module_get(Sanbase.Repo, :hostname),
           Application.get_env(:sanbase, :env)
         ) do
      :ok -> :ok
      {:error, reason} -> raise "Seeds can run only against a local database: #{reason}"
    end
  end

  @doc """
  The database host comes from `DATABASE_URL` when it is set, because
  `Sanbase.Repo.init/2` then connects there, and from the Repo config otherwise.
  """
  @spec check(String.t() | nil, String.t() | nil, atom()) :: :ok | {:error, String.t()}
  def check(_database_url, _hostname, :prod), do: {:error, "the environment is prod"}

  def check(database_url, hostname, _env) do
    host =
      case database_url do
        url when is_binary(url) and url != "" -> URI.parse(url).host
        _ -> hostname
      end

    if host in @local_hosts,
      do: :ok,
      else: {:error, "the database host is #{inspect(host)}"}
  end
end
