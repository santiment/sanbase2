defmodule Sanbase.Dashboards do
  @moduledoc ~s"""
  Dashboard is a collection of SQL queries and static widgets.

  Dashboards
  """

  alias Sanbase.Repo
  alias Sanbase.Queries.Query
  alias Sanbase.Queries.Dashboard
  alias Sanbase.Queries.DashboardQueryMapping

  import Sanbase.Utils.ErrorHandling, only: [changeset_errors_string: 1]

  # Type aliases
  @type dashboard_id :: Dashboard.dashboard_id()
  @type query_id :: Sanbase.Queries.Query.query_id()
  @type user_id :: Dashboard.user_id()
  @type create_dashboard_args :: Dashboard.create_dashboard_args()
  @type update_dashboard_args :: Dashboard.update_dashboard_args()
  @type dashboard_query_mapping_id :: DashboardQueryMapping.dashboard_query_mapping_id()

  @type visibility_data :: %{
          user_id: user_id(),
          is_public: boolean(),
          is_hidden: boolean()
        }

  @doc ~s"""
  Get a dashboard by id.

  The dashboard is returned if it exists and: is public, or if it is private
  and owned by the querying user. The queries are preloaded. If the queries
  should not be preloaded, provide `preload?: false` as an option.
  """
  @spec get_dashboard(dashboard_id(), user_id(), Keyword.t()) ::
          {:ok, Dashboard.t()} | {:error, String.t()}
  def get_dashboard(dashboard_id, querying_user_id, opts \\ []) do
    query = Dashboard.get_for_read(dashboard_id, querying_user_id, opts)

    case Repo.one(query) do
      %Dashboard{} = dashboard ->
        # TODO: Make some of the fields not viewable to the querying user
        # if the query is private but is added to a public dashboard
        # dashboard = mask_protected_fields(dashboard, querying_user_id)
        {:ok, dashboard}

      _ ->
        {:error,
         """
         Dashboard with id #{dashboard_id} does not exist, or it is private and owned by another user.
         """}
    end
  end

  @doc ~s"""
  Create a new empty dashboard.

  When creating a dashboard, the following parameters can be provided:
  - name: The name of the dashboard
  - description: The description of the dashboard
  - is_public: Whether the dashboard is public or not
  - user_id: The id of the user that created the query.

  Queries are added to the dashboard using the `add_query_to_dashboard/4` function.
  """
  @spec create_dashboard(user_id(), create_dashboard_args()) ::
          {:ok, Dashboard.t()} | {:error, String.t()}
  def create_dashboard(args, user_id) do
    args = args |> Map.merge(%{user_id: user_id})

    changeset = Dashboard.create_changeset(%Dashboard{}, args)

    case Repo.insert(changeset) do
      {:ok, dashboard} ->
        dashboard = Repo.preload(dashboard, [:queries, :user])
        {:ok, dashboard}

      {:error, changeset} ->
        {:error, changeset_errors_string(changeset)}
    end
  end

  @doc ~s"""
  TODO
  """
  @spec update_dashboard(dashboard_id(), update_dashboard_args(), user_id()) ::
          {:ok, Dashboard.t()} | {:error, String.t()}
  def update_dashboard(dashboard_id, args, querying_user_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_dashboard_for_mutation, fn _repo, _changes ->
      get_dashboard_for_mutation(dashboard_id, querying_user_id)
    end)
    |> Ecto.Multi.run(:update, fn _repo, %{get_dashboard_for_mutation: struct} ->
      changeset = Dashboard.update_changeset(struct, args)

      Repo.update(changeset)
    end)
    |> Repo.transaction()
    |> process_transaction_result(:update)
  end

  @doc ~s"""
  Add a new global parameter or overload an existing to a dashboard.

  A dashboard has a set of queries that each have their own parameters.
  Global parameters allow you to set a parameter that is shared across all queries.
  This can be useful if one wants to easily control all queries from one place -- change
  the asset, the time range, the limit in the LIMIT clause, etc.

  When adding a global parameter, the following parameters can be provided:
    - key: The name of the parameter.
    - value: The value of the parameter that will be used to override the query parameters.

  By default, the global parameter does not override anything, even if the names of the
  parameters match. Overriding a query parameter is done manually and explicitly by invoking
  put_global_parameter_override
  """
  @spec put_global_parameter(
          dashboard_id(),
          user_id(),
          Keyword.t()
        ) :: {:ok, Dashboard.t()} | {:error, String.t()}
  def put_global_parameter(dashboard_id, querying_user_id, opts) do
    key = Keyword.fetch!(opts, :key)
    value = Keyword.fetch!(opts, :value)

    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_dashboard_for_mutation, fn _repo, _changes ->
      get_dashboard_for_mutation(dashboard_id, querying_user_id)
    end)
    |> Ecto.Multi.run(:put_global_parameter, fn _repo, %{get_dashboard_for_mutation: struct} ->
      parameters = Map.put(struct.parameters, key, %{"value" => value, "overrides" => []})
      changeset = Dashboard.update_changeset(struct, %{parameters: parameters})

      Repo.update(changeset)
    end)
    |> Repo.transaction()
    |> process_transaction_result(:put_global_parameter)
  end

  @doc ~s"""
  Explicitly override a query parameter with a global parameter.

  In order to override a query parameter, the following parameters must be provided:
  - dashboard_id: The id of the dashboard that contains the query.
  - dashboard_query_mapping_id: The id of the mapping between the dashboard and the query.
    One query can be added multiple times to a dashboard, so the mapping id is used instead
    of query_id in order to uniquely identify the query.
  - querying_user_id: The id of the user who executes the function
  - opts: Keys `:local` and `:global` control the name of the query local and dashboard global
    parameters that are mapped.
  """
  @spec put_global_parameter_override(
          dashboard_id(),
          dashboard_query_mapping_id(),
          user_id(),
          Keyword.t()
        ) :: {:ok, Dashboard.t()} | {:error, String.t()}
  def put_global_parameter_override(
        dashboard_id,
        dashboard_query_mapping_id,
        querying_user_id,
        opts
      ) do
    local = Keyword.fetch!(opts, :local)
    global = Keyword.fetch!(opts, :global)

    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_dashboard_for_mutation, fn _repo, _changes ->
      get_dashboard_by_mapping_id_for_mutation(
        dashboard_id,
        dashboard_query_mapping_id,
        querying_user_id
      )
    end)
    |> Ecto.Multi.run(
      :put_override,
      fn _repo, %{get_dashboard_for_mutation: struct} ->
        case Map.get(struct.parameters, global) do
          nil ->
            {:error, "Parameter #{global} does not exist in dashboard with id #{dashboard_id}."}

          %{} = map ->
            elem = %{
              "dashboard_query_mapping_id" => dashboard_query_mapping_id,
              "parameter" => local
            }

            updated_parameter_map = Map.update(map, "overrides", [elem], &[elem | &1])
            parameters = Map.put(struct.parameters, global, updated_parameter_map)
            changeset = Dashboard.update_changeset(struct, %{parameters: parameters})

            Repo.update(changeset)
        end
      end
    )
    |> Repo.transaction()
    |> process_transaction_result(:put_override)
  end

  @doc ~s"""
  Delete a dashboard.

  Only the owner of a dashboard can delete it.
  """
  @spec delete_dashboard(dashboard_id(), user_id()) ::
          {:ok, Dashboard.t()} | {:error, Changeset.t()}
  def delete_dashboard(dashboard_id, querying_user_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_dashboard_for_mutation, fn _repo, _changes ->
      get_dashboard_for_mutation(dashboard_id, querying_user_id)
    end)
    |> Ecto.Multi.run(:delete, fn _repo, %{get_dashboard_for_mutation: struct} ->
      Repo.delete(struct)
    end)
    |> Repo.transaction()
    |> process_transaction_result(:delete)
  end

  @doc ~s"""
  Return a boolean showing if the dashboard is public or not.
  """
  @spec public?(Dashboard.t()) :: boolean()
  def public?(%Dashboard{is_public: is_public}), do: is_public

  @doc ~s"""
  Return a list of user dashboards.
  If the querying_user_id and user_id are the same, return all dashboards of that user.
  If the querying_user_id and user_id are different, or querying_user_id is nil (denoting
  anonymous user), return only the public dashboards of the user with id user_id
  """
  @spec user_dashboards(user_id(), user_id() | nil, Keyword.t()) :: {:ok, [Dashboard.t()]}
  def user_dashboards(user_id, querying_user_id, opts \\ []) do
    query = Dashboard.get_user_dashboards(user_id, querying_user_id, opts)

    {:ok, Repo.all(query)}
  end

  @doc ~s"""
  Return the subset of fields of a dashboard that are used to determine the visibility
  of the dashboard - who owns it, is it public, is it hidden.
  """
  @spec get_visibility_data(dashboard_id()) :: {:ok, visibility_data()} | {:error, String.t()}
  def get_visibility_data(dashboard_id) do
    query = get_visibility_data(dashboard_id)

    case Repo.one(query) do
      %{} = data -> {:ok, data}
      nil -> {:error, "Dashboard does not exist."}
    end
  end

  @doc ~s"""
  Add a query to a dashboard.

  One query can be added multiple times to a dashboard, with different settings.
  """
  @spec add_query_to_dashboard(dashboard_id(), query_id(), user_id(), Map.t()) ::
          {:ok, DashboardQueryMapping.t()} | {:error, String.t()}
  def add_query_to_dashboard(dashboard_id, query_id, querying_user_id, settings \\ %{}) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_dashboard_for_mutation, fn _repo, _changes ->
      # Only to make sure the user can mutate the dashboard. Do not preload any assoc
      get_dashboard_for_mutation(dashboard_id, querying_user_id, preload?: false)
    end)
    |> Ecto.Multi.run(:get_query_for_read, fn _repo, _changes ->
      # Only to make sure the user can read the query. Do not preload any assoc.
      get_query_for_read(query_id, querying_user_id, preload?: false)
    end)
    |> Ecto.Multi.run(:add_query_to_dashboard, fn _repo, _changes ->
      changeset =
        DashboardQueryMapping.changeset(%DashboardQueryMapping{}, %{
          dashboard_id: dashboard_id,
          query_id: query_id,
          settings: settings,
          user_id: querying_user_id
        })

      Repo.insert(changeset)
    end)
    |> Ecto.Multi.run(:add_preloads, fn _repo, %{add_query_to_dashboard: struct} ->
      {:ok, Repo.preload(struct, [:dashboard, [dashboard: :user], :query])}
    end)
    |> Repo.transaction()
    |> process_transaction_result(:add_preloads)
  end

  @doc ~s"""
  Remove a query from a dashboard.

  Only the user that owns the dashboard can remove queries from it. The entity to be removed
  is identified by the dashboard id and the dashboard query mapping id. One query can be
  added multiple times to a dashboard, so it is necessary to identify the exact mapping that
  needs to be removed.
  """
  @spec remove_query_from_dashboard(dashboard_id(), dashboard_query_mapping_id(), user_id()) ::
          {:ok, DashboardQueryMapping.t()} | {:error, String.t()}
  def remove_query_from_dashboard(dashboard_id, dashboard_query_mapping_id, querying_user_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_mapping, fn _repo, _changes ->
      query = DashboardQueryMapping.by_id(dashboard_query_mapping_id)

      case Repo.one(query) do
        %DashboardQueryMapping{dashboard: %{id: ^dashboard_id, user_id: ^querying_user_id}} = dqm ->
          {:ok, dqm}

        _ ->
          {:error, mapping_error(dashboard_query_mapping_id, dashboard_id, querying_user_id)}
      end
    end)
    |> Ecto.Multi.run(:remove_dashboard_query_mapping, fn _repo, %{get_mapping: struct} ->
      Repo.delete(struct)
    end)
    |> Ecto.Multi.run(:add_preloads, fn _repo, %{add_query_to_dashboard: struct} ->
      {:ok, Repo.preload(struct, [:dashboard, :query, :user])}
    end)
    |> Repo.transaction()
    |> process_transaction_result(:add_preloads)
  end

  @doc ~s"""
  Update the settings of a dashboard query mapping.
  """
  @spec update_dashboard_query(dashboard_id(), dashboard_query_mapping_id(), Map.t(), user_id()) ::
          {:ok, DashboardQueryMapping.t()} | {:error, String.t()}
  def update_dashboard_query(dashboard_id, dashboard_query_mapping_id, settings, querying_user_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_mapping, fn _repo, _changes ->
      query = DashboardQueryMapping.by_id(dashboard_query_mapping_id)

      case Repo.one(query) do
        %DashboardQueryMapping{dashboard: %{id: ^dashboard_id, user_id: ^querying_user_id}} = dqm ->
          {:ok, dqm}

        _ ->
          {:error, mapping_error(dashboard_query_mapping_id, dashboard_id, querying_user_id)}
      end
    end)
    |> Ecto.Multi.run(:update_mapping, fn _repo, %{get_mapping: struct} ->
      changeset = DashboardQueryMapping.changeset(struct, %{settings: settings})
      Repo.update(changeset)
    end)
    |> Ecto.Multi.run(:add_preloads, fn _repo, %{add_query_to_dashboard: struct} ->
      {:ok, Repo.preload(struct, [:dashboard, :query, :user])}
    end)
    |> Repo.transaction()
    |> process_transaction_result(:add_preloads)
  end

  # Private functions

  defp get_dashboard_by_mapping_id_for_mutation(
         dashboard_id,
         dashboard_query_mapping_id,
         querying_user_id
       ) do
    query = DashboardQueryMapping.by_id(dashboard_query_mapping_id)

    case Repo.one(query) do
      %{dashboard: %{id: ^dashboard_id, user_id: ^querying_user_id} = dashboard} ->
        {:ok, dashboard}

      _ ->
        {:error, mapping_error(dashboard_query_mapping_id, dashboard_id, querying_user_id)}
    end
  end

  defp get_dashboard_for_mutation(dashboard_id, querying_user_id, opts \\ []) do
    query = Dashboard.get_for_mutation(dashboard_id, querying_user_id, opts)

    case Repo.one(query) do
      %Dashboard{} = struct -> {:ok, struct}
      _ -> {:error, "Dashboard does not exist, or it is owner by another user."}
    end
  end

  defp get_query_for_read(query_id, querying_user_id, opts) do
    query = Query.get_for_read(query_id, querying_user_id, opts)

    case Repo.one(query) do
      %Query{} = struct -> {:ok, struct}
      _ -> {:error, "Query does not exist, or it is owned by another user and is private."}
    end
  end

  defp process_transaction_result({:ok, map}, ok_field),
    do: {:ok, map[ok_field]}

  defp process_transaction_result({:error, _, %Ecto.Changeset{} = changeset, _}, _ok_field),
    do: {:error, changeset_errors_string(changeset)}

  defp process_transaction_result({:error, _, error, _}, _ok_field),
    do: {:error, error}

  defp mapping_error(dashboard_query_mapping_id, dashboard_id, querying_user_id) do
    """
    Dashboard query mapping with id #{dashboard_query_mapping_id} does not exist,
    it is not part of dashboard #{dashboard_id}, or the dashboard is not owned by user #{querying_user_id}.
    """
  end
end
