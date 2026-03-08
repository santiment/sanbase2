defmodule SanbaseWeb.GenericAdmin do
  @moduledoc """
  Central registry and shared helpers for the GenericAdmin CRUD framework.

  GenericAdmin provides a configuration-driven admin interface for Ecto schemas
  that don't need custom LiveView pages. Each resource is defined by a module
  under `SanbaseWeb.GenericAdmin.*` that declares a `schema_module/0` callback
  and an optional `resource/0` configuration map.

  ## How it works

  1. **Discovery** — `custom_defined_modules/0` scans `:sanbase` application modules
     for any module whose name starts with `SanbaseWeb.GenericAdmin.`.

  2. **Configuration** — `resource_module_map/1` calls each discovered module's
     `schema_module/0` and `resource/0` to build a map of resource configs keyed
     by pluralized, underscored resource names (e.g. `"subscriptions"`).

  3. **Routing** — The `GenericAdminController` uses the `?resource=` query param
     to look up the config and render the appropriate CRUD page.

  ## Resource module callbacks

  Each `SanbaseWeb.GenericAdmin.*` module can implement:

  | Callback               | Required? | Description |
  |------------------------|-----------|-------------|
  | `schema_module/0`      | **yes**   | Returns the Ecto schema module (e.g. `Sanbase.Billing.Subscription`) |
  | `resource_name/0`      | no        | Override the auto-derived resource name |
  | `resource/0`           | no        | Map with `:actions`, `:index_fields`, `:new_fields`, `:edit_fields`, `:fields_override`, `:belongs_to_fields`, `:preloads`, `:custom_index_actions` |
  | `before_filter/1`      | no        | Transform a record before display (receives and returns struct) |
  | `after_filter/3`       | no        | Hook called after create/update (receives `record, changeset, changes`) |
  | `has_many/1`           | no        | Return list of has_many table definitions for the show page |
  | `belongs_to/1`         | no        | Return list of belongs_to detail sections for the show page |

  ## fields_override options

  The `:fields_override` map keys are field atoms and values are maps with:

  - `:value_modifier` — `(record -> any)` function to customize display value
  - `:collection` — list of `{label, value}` tuples for select dropdowns
  - `:type` — override the Ecto field type (e.g. `:multiselect`)
  - `:search_query` — custom search query builder for this field
  """

  @doc "The Ecto schema module backing this admin resource."
  @callback schema_module() :: module()

  @doc "Plural resource name used in URLs and index pages (e.g. \"projects\")."
  @callback resource_name() :: String.t()

  @doc "Singular resource name used in labels and show pages (e.g. \"project\")."
  @callback singular_resource_name() :: String.t()

  @doc """
  Returns all modules under the `SanbaseWeb.GenericAdmin.*` namespace.

  Uses `:application.get_key/2` to scan loaded modules at runtime.
  """
  def custom_defined_modules() do
    case :application.get_key(:sanbase, :modules) do
      {:ok, modules} ->
        modules
        |> Enum.filter(fn module ->
          String.starts_with?(Atom.to_string(module), "Elixir.SanbaseWeb.GenericAdmin.")
        end)

      _ ->
        []
    end
  end

  @doc """
  Builds a map of all resource configurations, keyed by resource name.

  Each entry contains the schema module, admin module, field lists, actions
  (filtered by the current user's roles from `conn`), and any overrides.

  When `conn` is not provided (e.g. during search routing), role-based
  action filtering is skipped.
  """
  def resource_module_map(%Plug.Conn{} = conn \\ %Plug.Conn{}) do
    Enum.reduce(custom_defined_modules(), %{}, fn admin_module, acc ->
      Map.merge(acc, generate_resource(conn, admin_module))
    end)
  end

  defp generate_resource(conn, admin_module) when is_atom(admin_module) do
    schema_module = admin_module.schema_module()

    resource_name = admin_module.resource_name()
    singular = admin_module.singular_resource_name()

    %{
      resource_name =>
        %{
          module: schema_module,
          admin_module: admin_module,
          singular: singular,
          actions: [],
          index_fields: :all,
          new_fields: [],
          edit_fields: [],
          funcs: %{}
        }
        |> Map.merge(call_module_function_or_default(admin_module, :resource, [], %{}))
        |> Map.update(:actions, [], fn actions ->
          actions = ([:show] ++ actions) |> Enum.uniq()

          if actions -- [:show, :new, :edit, :delete] != [],
            do:
              raise(ArgumentError,
                message:
                  "Unexpected action(s) in GenericAdmin: #{Enum.join(actions -- [:show, :edit, :delete], ", ")}"
              )

          # In some cases (like searching) we only want to get the resources and won't care about the
          # action buttons. In these cases `conn` will not be passed and the default empty conn will be
          # provided. Treat this as no roles
          roles = conn.assigns[:current_user_role_names] || []

          can_fn = fn action -> Sanbase.Admin.Permissions.can?(action, roles: roles) end

          actions
          |> then(fn l -> if can_fn.(:new), do: l, else: l -- [:new] end)
          |> then(fn l -> if can_fn.(:edit), do: l, else: l -- [:edit] end)
          |> then(fn l -> if can_fn.(:delete), do: l, else: l -- [:delete] end)
        end)
    }
  end

  @doc """
  Returns a list of all resource name strings (e.g. `["subscriptions", "users", ...]`).
  Used by the controller to generate navigation routes.
  """
  def resources do
    custom_defined_modules()
    |> Enum.map(fn admin_module -> admin_module.resource_name() end)
  end

  @doc """
  Safely calls a function on a resource module, falling back to `default_value`
  if the function is not exported. Used to make all resource callbacks optional.
  """
  def call_module_function_or_default(module, function, data, default_value) do
    if function_exported?(module, function, length(data)) do
      apply(module, function, data)
    else
      default_value
    end
  end

  @doc """
  Derives a URL-friendly resource name from an Ecto schema module.

  ## Example

      iex> schema_to_resource_name(Sanbase.Billing.Subscription)
      "subscriptions"
  """
  def schema_to_resource_name(schema_module) do
    schema_module
    |> to_string()
    |> String.split(".")
    |> List.last()
    |> Inflex.underscore()
    |> Inflex.pluralize()
  end

  # ---------------------------------------------------------------------------
  # Shared helpers for resource modules
  # ---------------------------------------------------------------------------

  @doc """
  Generates an HTML link to a GenericAdmin show page for a given resource.
  Used by resource modules to create clickable links in value_modifier functions.
  """
  def resource_link(resource, id, label) do
    relative_url =
      SanbaseWeb.Router.Helpers.generic_admin_path(SanbaseWeb.Endpoint, :show, id,
        resource: resource
      )

    PhoenixHTMLHelpers.Link.link(label,
      to: relative_url,
      class: "text-blue-600 hover:text-blue-800"
    )
  end

  @doc """
  Common belongs_to definition for Project associations.
  Used by many resource modules that have a project_id foreign key.
  """
  def belongs_to_project do
    import Ecto.Query, only: [from: 2], warn: false

    %{
      query: from(p in Sanbase.Project, order_by: p.id),
      transform: fn rows -> Enum.map(rows, &{&1.name, &1.id}) end,
      resource: "projects",
      search_fields: [:name, :slug, :ticker]
    }
  end

  @doc """
  Common belongs_to definition for User associations.
  Used by resource modules that have a user_id foreign key.
  """
  def belongs_to_user do
    import Ecto.Query, only: [from: 2], warn: false

    %{
      query: from(u in Sanbase.Accounts.User, order_by: [desc: u.id]),
      transform: fn rows -> Enum.map(rows, &{&1.email, &1.id}) end,
      resource: "users",
      search_fields: [:email, :username]
    }
  end
end
