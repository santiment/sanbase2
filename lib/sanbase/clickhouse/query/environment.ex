defmodule Sanbase.Clickhouse.Query.Environment do
  @moduledoc ~s"""
  Each query is executed in an execution environment.

  An environment is represented as its bindings -- a map of key-value pairs.
  The environment bindings are provided by Santiment Backend. The bindings
  could be different for different users. Such an example is the `@me`/`@owner`
  binding, which refers to the owner of the query/dashboard.
  Other bindings are the same for everyone -- like the `@assets` binding, which
  is map, where the key is an asset's slug like `bitcoin`, and the value is another
  map with the asset's data -- name, ticker, description, github organizations,
  contract addresses, etc.

  An example showing why it is needed: A Dashboard creator wants to add an
  'About me' text widget in the top right corner of all of their dashboards.
  It includes the author name, email, twitter, and telegram handle.
  What would happen if that person wants to change their email address?
  They don't need to go through all of their dashboards and change the email manually.
  The user can use the `@me` environment variable that is populated automatically
  with the query/dashboard owner details -- they just need to use a template and an
  env var like this -- `{{@me["email"]}}
  """

  alias Sanbase.Accounts.User
  alias Sanbase.Dashboards.Dashboard
  alias Sanbase.Queries.Query

  defstruct owner: nil,
            executor: nil,
            assets: []

  @type contract_address :: %{
          address: String.t(),
          decimals: non_neg_integer(),
          label: String.t()
        }

  @type user_subset :: %{
          id: non_neg_integer(),
          username: String.t() | nil,
          email: String.t() | nil,
          name: String.t() | nil
        }

  @type asset :: %{
          slug: String.t(),
          ticker: String.t(),
          name: String.t(),
          contract_addresses: [contract_address()],
          github_organizations: [String.t()]
        }

  @type t :: %__MODULE__{
          owner: user_subset | nil,
          executor: user_subset | nil,
          assets: [asset]
        }

  @spec empty() :: t()
  def empty, do: %__MODULE__{}

  @spec new(Dashboard.t(), User.t()) :: {:ok, t()} | {:error, String.t()}
  @spec new(Query.t(), User.t()) :: {:ok, t()} | {:error, String.t()}
  def new(%Dashboard{} = dashboard, %User{} = querying_user) do
    with {:ok, assets} <- get_assets() do
      env = %__MODULE__{
        owner: user_subset(dashboard.user),
        executor: user_subset(querying_user),
        assets: assets
      }

      {:ok, env}
    end
  end

  def new(%Query{} = query, %User{} = querying_user) do
    case get_assets() do
      {:ok, assets} ->
        env = %__MODULE__{
          owner: user_subset(query.user),
          executor: user_subset(querying_user),
          assets: assets
        }

        {:ok, env}

      {:error, reason} ->
        {:error, "Error loading the Execution Enviornment. Reason: #{inspect(reason)}"}
    end
  end

  @spec queries_env(Dashboard.t(), User.t()) :: {:ok, t()} | {:error, String.t()}
  @spec queries_env(Query.t(), User.t()) :: {:ok, t()} | {:error, String.t()}
  def queries_env(%Dashboard{} = dashboard, %User{} = querying_user) do
    with {:ok, assets} <- get_assets() do
      env = %__MODULE__{
        owner: user_subset(dashboard.user),
        executor: user_subset(querying_user),
        assets: assets
      }

      {:ok, env}
    end
  end

  def queries_env(%Query{} = query, %User{} = querying_user) do
    case get_assets() do
      {:ok, assets} ->
        env = %__MODULE__{
          owner: user_subset(query.user),
          executor: user_subset(querying_user),
          assets: assets
        }

        {:ok, env}

      {:error, reason} ->
        {:error, "Error loading the Execution Enviornment. Reason: #{inspect(reason)}"}
    end
  end

  # Private functions

  defp get_assets do
    Sanbase.Cache.get_or_store({{__MODULE__, :get_assets}}, fn ->
      list = Sanbase.Project.List.projects_data_for_queries()
      {:ok, list}
    end)
  end

  defp user_subset(%User{} = user) do
    user
    |> Map.from_struct()
    |> Map.take([:id, :username, :email, :name])
  end
end
