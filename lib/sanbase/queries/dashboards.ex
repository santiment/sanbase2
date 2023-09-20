defmodule Sanbase.Dashboards do
  @moduledoc ~s"""
  Dashboard is a collection of SQL queries and static widgets.
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
        {:ok, mask_dashboard_not_viewable_parts(dashboard)}

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
  There are corresponding functions for updating/removing dashboard queries.

  Global parameters can be added to the dashboard using the `add_global_parameter/3` function.
  There are corresponding functions for updating/removing global parameters.

  When neededing to override a query local parameter with a global parameter, use the
  `add_global_parameter_override/4` function.
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
  Update a dashboard
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
  Delete a dashboard

  Only the owner of the dashboard can delete it
  """
  @spec delete_dashboard(dashboard_id(), user_id()) ::
          {:ok, Dashboard.t()} | {:error, String.t()}
  def delete_dashboard(dashboard_id, querying_user_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_dashboard_for_mutation, fn _repo, _changes ->
      get_dashboard_for_mutation(dashboard_id, querying_user_id)
    end)
    |> Ecto.Multi.run(:delete_dashboard, fn _repo, %{get_dashboard_for_mutation: struct} ->
      Repo.delete(struct)
    end)
    |> Repo.transaction()
    |> process_transaction_result(:delete_dashboard)
  end

  @doc ~s"""
  Replace local parameters with the correct global parameter overrides.

  The global parameters are defined on the dashboard level and have the following
  structure:
  %{
    "slug" => %{
      "value" => "bitcoin",
      "overrides" => [%{"dashboard_query_mapping_id" => 101, "parameter" => "slug"}]
    }
  }

  When a query `q` added to the dashboard, with dashboard-query mapping id `dq_id`,
  is executed, the parameters are resolved in the following way:
  - Iterate over the global parameters;
  - Find those who have `dq_id` in their overrides;
  - Extract the key-value pairs from the overrides;
  - Replace the parameters in `q` with the overrides.
  """
  @spec apply_global_parameters(Query.t(), Dashboard.t(), non_neg_integer()) ::
          {:ok, Query.t()}
  def apply_global_parameters(
        %Query{} = query,
        %Dashboard{} = dashboard,
        mapping_id
      ) do
    # Walk over the dashboard global parameters and extract a map, where the keys
    # are parameters of the query and the values are the global values that will
    # override the query values (like %{"slug" => "global_slug_value"}).
    # The name of the global parameter is not needed, only the value and the list
    # of overrides.
    overrides =
      dashboard.parameters
      |> Enum.reduce(
        %{},
        fn {_key, %{"value" => value, "overrides" => overrides}}, acc ->
          case Enum.find(overrides, &(&1["dashboard_query_mapping_id"] == mapping_id)) do
            nil -> acc
            %{"parameter" => parameter} -> Map.put(acc, parameter, value)
          end
        end
      )

    new_sql_query_parameters = Map.merge(query.sql_query_parameters, overrides)

    query = %Query{query | sql_query_parameters: new_sql_query_parameters}
    {:ok, query}
  end

  @doc ~s"""
  Add a new global parameter or overload an existing to a dashboard.

  A dashboard has a set of queries that each have their own parameters.
  Global parameters allow you to set a parameter that is shared across all queries.
  This can be useful if one wants to easily control all queries from one place -- change
  the asset, the time range, the limit in the LIMIT clause, etc.

  When adding a global parameter, the following opts can be provided:
    - key: The name of the parameter.
    - value: The value of the parameter that will be used to override the query parameters.

  By default, the global parameter does not override anything, even if the names of the
  parameters match. Overriding a query parameter is done manually and explicitly by invoking
  add_global_parameter_override.
  """
  @spec add_global_parameter(
          dashboard_id(),
          user_id(),
          Keyword.t()
        ) :: {:ok, Dashboard.t()} | {:error, String.t()}
  def add_global_parameter(dashboard_id, querying_user_id, opts) do
    key = Keyword.fetch!(opts, :key)
    value = Keyword.fetch!(opts, :value)

    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_dashboard_for_mutation, fn _repo, _changes ->
      get_dashboard_for_mutation(dashboard_id, querying_user_id)
    end)
    |> Ecto.Multi.run(:add_global_parameter, fn _repo, %{get_dashboard_for_mutation: struct} ->
      parameters = Map.put(struct.parameters, key, %{"value" => value, "overrides" => []})
      changeset = Dashboard.update_changeset(struct, %{parameters: parameters})

      Repo.update(changeset)
    end)
    |> Repo.transaction()
    |> process_transaction_result(:add_global_parameter)
  end

  @doc ~s"""
  Update a global parameter.

  When updating a global parameters, the following opts can be provided:
    - key: The name of the parameter.
    - new_key (optional): The new name of the parameter.
    - new_value (optional): The new value of the parameter that will be used to override the query parameters.
  """
  @spec update_global_parameter(dashboard_id(), user_id(), Keyword.t()) ::
          {:ok, Dashboard.t()} | {:error, String.t()}
  def update_global_parameter(dashboard_id, querying_user_id, opts) do
    key = Keyword.fetch!(opts, :key)
    new_key = Keyword.get(opts, :new_key, nil)
    new_value = Keyword.get(opts, :new_value, nil)

    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_dashboard_for_mutation, fn _repo, _changes ->
      get_dashboard_for_mutation(dashboard_id, querying_user_id)
    end)
    |> Ecto.Multi.run(:update_global_parameter, fn _repo, %{get_dashboard_for_mutation: struct} ->
      case Map.get(struct.parameters, key) do
        nil ->
          {:error, "Dashboard parameter with key #{key} does not exist."}

        map ->
          updated_key = if new_key, do: new_key, else: key
          updated_value = if new_value, do: Map.put(map, "value", new_value), else: map

          updated_parameters =
            struct.parameters
            # Just Map.put/3 in case of updated key will leave the old key in the map and the
            # overrides will continue to work.
            |> Map.delete(key)
            |> Map.put(updated_key, updated_value)

          changeset = Dashboard.update_changeset(struct, %{parameters: updated_parameters})

          Repo.update(changeset)
      end
    end)
    |> Repo.transaction()
    |> process_transaction_result(:update_global_parameter)
  end

  @doc ~s"""
  Delete a global parameter
  """
  @spec delete_global_parameter(dashboard_id(), user_id(), String.t()) ::
          {:ok, Dashboard.t()} | {:error, String.t()}
  def delete_global_parameter(dashboard_id, querying_user_id, key) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_dashboard_for_mutation, fn _repo, _changes ->
      get_dashboard_for_mutation(dashboard_id, querying_user_id)
    end)
    |> Ecto.Multi.run(:delete_global_parameter, fn _repo, %{get_dashboard_for_mutation: struct} ->
      parameters = Map.delete(struct.parameters, key)
      changeset = Dashboard.update_changeset(struct, %{parameters: parameters})

      Repo.update(changeset)
    end)
    |> Repo.transaction()
    |> process_transaction_result(:delete_global_parameter)
  end

  @doc ~s"""
  Explicitly override a query parameter with a global parameter.

  In order to override a query parameter, the following parameters must be provided:
  - dashboard_id: The id of the dashboard that contains the query.
  - dashboard_query_mapping_id: The id of the mapping between the dashboard and the query.
    One query can be added multiple times to a dashboard, so the mapping id is used instead
    of query_id in order to uniquely identify the query.
  - querying_user_id: The id of the user who executes the function
  - opts: Keys `:query_parameter_key` and `:dashboard_parameter_key` control the name of the query local and dashboard global
    parameters that are mapped.

  The global parameters are defined on the dashboard level and have the following format:

    %{
      "slug" => %{
        "value" => "bitcoin",
        "overrides" => [%{"dashboard_query_mapping_id" => 101, "parameter" => "slug"}]
      },
      "another_key" => %{
        "value" => "another_value",
        "overrides" => [%{"dashboard_query_mapping_id" => 101, "parameter" => "another_key"}]
      }
    }

  Here the top-level value is the `key` of the global parameter. The value of the global parameter
  is another map that defines the `value` and the list of `overrides`. The `overrides` list contains
  information which query and which parameter in that query to override.
  """
  @spec add_global_parameter_override(
          dashboard_id(),
          dashboard_query_mapping_id(),
          user_id(),
          Keyword.t()
        ) :: {:ok, Dashboard.t()} | {:error, String.t()}
  def add_global_parameter_override(
        dashboard_id,
        dashboard_query_mapping_id,
        querying_user_id,
        opts
      ) do
    query_key = Keyword.fetch!(opts, :query_parameter_key)
    dashboard_key = Keyword.fetch!(opts, :dashboard_parameter_key)

    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_dashboard_for_mutation, fn _repo, _changes ->
      get_dashboard_by_mapping_id_for_mutation(
        dashboard_id,
        dashboard_query_mapping_id,
        querying_user_id
      )
    end)
    |> Ecto.Multi.run(
      :add_parameter_override,
      fn _repo, %{get_dashboard_for_mutation: struct} ->
        case Map.get(struct.parameters, dashboard_key) do
          nil ->
            {:error,
             "Parameter #{dashboard_key} does not exist in dashboard with id #{dashboard_id}."}

          %{} = map ->
            elem = %{
              "dashboard_query_mapping_id" => dashboard_query_mapping_id,
              "parameter" => query_key
            }

            updated_parameter_map = Map.update(map, "overrides", [elem], &[elem | &1])
            parameters = Map.put(struct.parameters, dashboard_key, updated_parameter_map)
            changeset = Dashboard.update_changeset(struct, %{parameters: parameters})

            Repo.update(changeset)
        end
      end
    )
    |> Repo.transaction()
    |> process_transaction_result(:add_parameter_override)
  end

  @doc ~s"""
  Delete a global parameter override for a query mapping.

  Given the follwoing global parameters:

  %{
    "slug" => %{
      "value" => "bitcoin",
      "overrides" => [%{"dashboard_query_mapping_id" => 101, "parameter" => "slug"}]
    },
    "another_key" => %{
      "value" => "another_value",
      "overrides" => [%{"dashboard_query_mapping_id" => 101, "parameter" => "another_key"}]
    }
  }

  When deleting the override for the slug parameter and dashboard_query_mapping_id 101, the result will be:
  %{
    "slug" => %{
      "value" => "bitcoin",
      "overrides" => []
    },
    "another_key" => %{
      "value" => "another_value",
      "overrides" => [%{"dashboard_query_mapping_id" => 101, "parameter" => "another_key"}]
    }
  }
  """
  @spec delete_global_parameter_override(
          dashboard_id(),
          dashboard_query_mapping_id(),
          user_id(),
          String.t()
        ) :: {:ok, Dashboard.t()} | {:error, String.t()}
  def delete_global_parameter_override(
        dashboard_id,
        dashboard_query_mapping_id,
        querying_user_id,
        global_key
      ) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_dashboard_for_mutation, fn _repo, _changes ->
      get_dashboard_by_mapping_id_for_mutation(
        dashboard_id,
        dashboard_query_mapping_id,
        querying_user_id
      )
    end)
    |> Ecto.Multi.run(
      :delete_global_parameter_override,
      fn _repo, %{get_dashboard_for_mutation: struct} ->
        case Map.get(struct.parameters, global_key) do
          nil ->
            {:error,
             "Parameter #{global_key} does not exist in dashboard with id #{dashboard_id}."}

          %{} = map ->
            updated_overrides =
              Enum.reject(
                map["overrides"],
                &(&1["dashboard_query_mapping_id"] == dashboard_query_mapping_id)
              )

            updated_parameter_map = Map.put(map, "overrides", updated_overrides)
            updated_parameters = Map.put(struct.parameters, global_key, updated_parameter_map)
            changeset = Dashboard.update_changeset(struct, %{parameters: updated_parameters})

            Repo.update(changeset)
        end
      end
    )
    |> Repo.transaction()
    |> process_transaction_result(:delete_global_parameter_override)
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

  defp mask_dashboard_not_viewable_parts(%Dashboard{} = dashboard) do
    # TODO: Make sure if this is the desired behavior.
    # When viewing a dashboard, hide the SQL query text and query parameters
    # if the query is private and the querying user is not the owner of the query
    masked_queries =
      dashboard.queries
      |> Enum.map(&mask_query_not_viewable_parts(&1, dashboard.user_id))

    %Dashboard{dashboard | queries: masked_queries}
  end

  defp mask_query_not_viewable_parts(
         %Query{user_id: query_owner_user_id, is_public: false} = query,
         dashboard_owner_user_id
       )
       when query_owner_user_id != dashboard_owner_user_id do
    %Query{
      query
      | sql_query_text: "<masked>",
        sql_query_parameters: %{}
    }
  end

  defp mask_query_not_viewable_parts(query, _dashboard_owner_user_id), do: query
end
