defmodule Sanbase.ClickhouseRepo.ReadOnly do
  @moduledoc ~s"""
  Clickhouse repo with read-only access.

  This module defines a clickhouse repo that is started with read-only
  credentials.
  It does not define any of the query functions as it is not indended to be
  used directly. Instead, in the process that requires read-only restricted
  access, the repo is put as the dynamic repo with the following code:
  `Sanbase.ClickhouseRepo.put_dynamic_repo(Sanbase.ClickhouseRepo.ReadOnly)`
  After that, the user can execute queries written by the user using the same
  ClickhouseRepo functions, but the connection pool used is the one configured
  by this module
  """
  use Ecto.Repo,
    otp_app: :sanbase,
    adapter: if(Mix.env() == :test, do: Ecto.Adapters.Postgres, else: ClickhouseEcto),
    read_only: true,
    default_dynamic_repo: if(Mix.env() == :test, do: Sanbase.ClickhouseRepo, else: Sanbase.ClickhouseRepo.ReadOnly)

  alias Sanbase.Utils.Config

  def init(_, opts) do
    pool_size = __MODULE__ |> Config.module_get(:pool_size) |> Sanbase.Math.to_integer()

    opts =
      opts
      |> Keyword.put(:url, System.get_env("CLICKHOUSE_READONLY_DATABASE_URL"))
      |> Keyword.put(:pool_size, pool_size)
      |> Keyword.put(:username, "sql_dashboard_user")

    {:ok, opts}
  end
end

defmodule Sanbase.ClickhouseRepo.FreeUser do
  @moduledoc false
  use Ecto.Repo, otp_app: :sanbase, adapter: ClickhouseEcto, read_only: true

  def init(do_init, opts) do
    {:ok, default_opts} = Sanbase.ClickhouseRepo.ReadOnly.init(do_init, opts)
    new_opts = Keyword.put(default_opts, :username, "free_user")
    {:ok, new_opts}
  end
end

defmodule Sanbase.ClickhouseRepo.SanbaseProUser do
  @moduledoc false
  use Ecto.Repo, otp_app: :sanbase, adapter: ClickhouseEcto, read_only: true

  def init(do_init, opts) do
    {:ok, default_opts} = Sanbase.ClickhouseRepo.ReadOnly.init(do_init, opts)
    new_opts = Keyword.put(default_opts, :username, "sanbase_pro_user")
    {:ok, new_opts}
  end
end

defmodule Sanbase.ClickhouseRepo.SanbaseMaxUser do
  @moduledoc false
  use Ecto.Repo, otp_app: :sanbase, adapter: ClickhouseEcto, read_only: true

  def init(do_init, opts) do
    {:ok, default_opts} = Sanbase.ClickhouseRepo.ReadOnly.init(do_init, opts)
    new_opts = Keyword.put(default_opts, :username, "sanbase_max_user")
    {:ok, new_opts}
  end
end

defmodule Sanbase.ClickhouseRepo.BusinessProUser do
  @moduledoc false
  use Ecto.Repo, otp_app: :sanbase, adapter: ClickhouseEcto, read_only: true

  def init(do_init, opts) do
    {:ok, default_opts} = Sanbase.ClickhouseRepo.ReadOnly.init(do_init, opts)
    new_opts = Keyword.put(default_opts, :username, "business_pro_user")
    {:ok, new_opts}
  end
end

defmodule Sanbase.ClickhouseRepo.BusinessMaxUser do
  @moduledoc false
  use Ecto.Repo, otp_app: :sanbase, adapter: ClickhouseEcto, read_only: true

  def init(do_init, opts) do
    {:ok, default_opts} = Sanbase.ClickhouseRepo.ReadOnly.init(do_init, opts)
    new_opts = Keyword.put(default_opts, :username, "business_max_user")
    {:ok, new_opts}
  end
end
