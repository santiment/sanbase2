# GenericAdmin Architecture

The GenericAdmin framework provides a configuration-driven CRUD admin interface
for Ecto schemas that don't need custom LiveView pages.

## System Overview

```mermaid
graph TB
    subgraph Browser
        USER[Admin User]
    end

    subgraph Router["Phoenix Router"]
        ROUTES["/admin/generic?resource=X"]
    end

    subgraph Controller["GenericAdminController"]
        HOME[home]
        INDEX[index]
        SHOW[show]
        NEW[new]
        CREATE[create]
        EDIT[edit]
        UPDATE[update]
        DELETE[delete]
        SEARCH[search]
        SHOW_ACTION[show_action]
    end

    subgraph Registry["SanbaseWeb.GenericAdmin"]
        DISCOVER[custom_defined_modules/0<br/>Scans :sanbase app modules]
        RESMAP[resource_module_map/1<br/>Builds config per resource]
        HELPERS[Shared Helpers<br/>resource_link/3<br/>belongs_to_project/0<br/>belongs_to_user/0]
    end

    subgraph ResourceModules["SanbaseWeb.GenericAdmin.*"]
        RM1[Ecosystem]
        RM2[Subscription]
        RM3[User]
        RM_N["... 16 more"]
    end

    subgraph Templates["HEEx Templates"]
        T_HOME[home.html.heex]
        T_INDEX[index.html.heex]
        T_SHOW[show.html.heex]
        T_FORM[form.html.heex]
    end

    subgraph Components["AdminComponents"]
        C_TABLE[table / thead / tbody]
        C_SHOW[show_table]
        C_HM[has_many_table]
        C_FORM[form_input / form_select]
        C_SEARCH[search]
        C_NAV[pagination / btn / action_btn]
    end

    subgraph Data["Ecto / Repo"]
        SCHEMA[Ecto Schema]
        DB[(PostgreSQL)]
    end

    USER --> ROUTES
    ROUTES --> HOME & INDEX & SHOW & NEW & CREATE & EDIT & UPDATE & DELETE & SEARCH & SHOW_ACTION

    INDEX & SHOW & NEW & CREATE & EDIT & UPDATE & SEARCH --> RESMAP
    RESMAP --> DISCOVER
    DISCOVER --> RM1 & RM2 & RM3 & RM_N

    HOME --> T_HOME
    INDEX & SEARCH --> T_INDEX
    SHOW --> T_SHOW
    NEW & EDIT --> T_FORM
    CREATE & UPDATE --> |save_and_redirect| SCHEMA

    T_INDEX --> C_TABLE & C_SEARCH & C_NAV
    T_SHOW --> C_SHOW & C_HM
    T_FORM --> C_FORM

    C_TABLE & C_SHOW & C_HM --> SCHEMA
    SCHEMA --> DB
```

## Request Flow

```mermaid
sequenceDiagram
    participant B as Browser
    participant R as Router
    participant C as Controller
    participant G as GenericAdmin Registry
    participant M as Resource Module
    participant DB as PostgreSQL
    participant T as Template + Components

    B->>R: GET /admin/generic?resource=users
    R->>C: index(conn, %{"resource" => "users"})

    C->>G: resource_module_map(conn)
    G->>G: custom_defined_modules()
    G->>M: schema_module(), resource()
    M-->>G: Sanbase.Accounts.User, %{actions: [...], ...}
    G-->>C: %{"users" => %{module: User, actions: [...], ...}}

    C->>C: resource_params(conn, "users", :index)
    Note right of C: Computes fields, types,<br/>overrides, funcs, collections

    C->>DB: Repo.all(from u in User, ...)
    DB-->>C: [%User{}, ...]

    C->>M: before_filter(record) per row
    M-->>C: transformed records

    C->>T: render("index.html", table: %{...})
    T->>T: AdminComponents.table → thead + tbody
    T-->>B: HTML response
```

## Create/Update Flow

```mermaid
sequenceDiagram
    participant B as Browser
    participant C as Controller
    participant G as GenericAdmin Registry
    participant M as Resource Module
    participant DB as PostgreSQL

    B->>C: POST /admin/generic?resource=users (create)<br/>or PATCH /admin/generic/:id?resource=users (update)

    C->>G: resource_module_map(conn)
    G-->>C: resource config

    C->>C: transform_changes(params, field_type_map)
    Note right of C: Decodes JSON for map/array fields

    C->>C: Module.changeset(struct_or_data, changes)
    Note right of C: Uses create_changeset/2 or<br/>update_changeset/2 if defined

    C->>C: save_and_redirect(conn, :create/:update, ...)
    C->>DB: Repo.insert/update(changeset)

    alt Success
        DB-->>C: {:ok, record}
        C->>M: after_filter(record, changeset, changes)
        M-->>C: :ok or {:error, reason}
        C-->>B: Redirect to show page with flash
    else Validation Error
        DB-->>C: {:error, changeset}
        C-->>B: Re-render form with errors
    end
```

## Resource Module Configuration

```mermaid
classDiagram
    class ResourceModule {
        +schema_module() :: module
        +resource_name() :: String.t [optional]
        +resource() :: map [optional]
        +before_filter(record) :: record [optional]
        +after_filter(record, changeset, changes) [optional]
        +has_many(record) :: list [optional]
        +belongs_to(record) :: list [optional]
    }

    class ResourceConfig {
        module : Ecto schema module
        admin_module : GenericAdmin.* module
        singular : String.t
        actions : [:show, :new, :edit, :delete]
        index_fields : :all | [atom]
        new_fields : [atom]
        edit_fields : [atom]
        preloads : [atom]
        fields_override : map
        belongs_to_fields : map
        custom_index_actions : list
        funcs : map
    }

    class FieldOverride {
        value_modifier : (record -> any)
        collection : [{label, value}]
        type : atom
        search_query : Ecto.Query
    }

    class BelongsToField {
        query : Ecto.Query
        transform : (rows -> [{label, value}])
        resource : String.t
        search_fields : [atom]
    }

    ResourceModule --> ResourceConfig : produces via resource/0
    ResourceConfig --> FieldOverride : fields_override values
    ResourceConfig --> BelongsToField : belongs_to_fields values
```

## File Structure

```
lib/sanbase_web/
├── generic_admin.ex                          # Registry + shared helpers
├── generic_admin/
│   ├── ARCHITECTURE.md                       # This file
│   ├── ecosystem.ex                          # Resource: Ecosystem
│   ├── subscription.ex                       # Resource: Subscription, Plan, Product, PromoTrial
│   ├── user.ex                               # Resource: User
│   ├── project.ex                            # Resource: Project + related
│   ├── post.ex                               # Resource: Post
│   ├── ... (19 resource modules total)
│   └── version.ex                            # Resource: Version
├── controllers/
│   └── generic_admin_controller.ex           # CRUD controller + LinkBuilder
├── components/admin/
│   └── admin_components.ex                   # Phoenix function components
└── templates/generic_admin_html/
    ├── home.html.heex                        # Admin home / navigation
    ├── index.html.heex                       # Resource listing (search + table)
    ├── show.html.heex                        # Resource detail (show_table + has_many)
    └── form.html.heex                        # Unified new/edit form
```
