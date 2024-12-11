# Adding Comments capabilities to a new entity

All comments are stored in the `comments` database table.
For every entity there is a mapping table like `dashboard_comments_mapping` that
maps a comment to an entity. This way when adding a new comment entity only the
mapping table needs to be created.

The following steps need to be done in order to add comments to a new entity.

1. Add database mapping table. A mapping table looks like this and only the
   names and references need to be changed.
```elixir
  @table :dashboard_comments_mapping
  def change do
    create(table(@table)) do
      add(:comment_id, references(:comments, on_delete: :delete_all))
      add(:dashboard_id, references(:dashboards, on_delete: :delete_all))

      timestamps()
    end

    create(unique_index(@table, [:comment_id]))
    create(index(@table, [:dashboard_id]))
  end
```

2. Add a Comment mapping module that holds the schema. Example:
```elixir
defmodule Sanbase.Comment.DashboardComment do
  @moduledoc ~s"""
  A mapping table connecting comments and timeline events.

  This module is used to create, update, delete and fetch timeline events comments.
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "dashboard_comments_mapping" do
    belongs_to(:comment, Sanbase.Comment)
    belongs_to(:dashboard, Sanbase.UserList)

    timestamps()
  end

  def changeset(%__MODULE__{} = mapping, attrs \\ %{}) do
    mapping
    |> cast(attrs, [:dashboard_id, :comment_id])
    |> validate_required([:dashboard_id, :comment_id])
    |> unique_constraint(:comment_id)
  end
end
```

3. Update the `Comment` module
- Add a many_to_many association

1. Update the EntityComment module:
- Extend the defined types with the new module
- Extend the defined module attributes with the new module
- Add a `link/3` function
- Add a `entity_comments_query/2` function
- Extend the `all_feed_comments_query/0` function
- If necessary, add a function like `exclude_not_public_chart_configurations/1`

5. Update the APIs
- Add the entity type to the `CommentTypes` module
  - Add the type to the enum
  - Add the type to the object
  - Add a field with a resolver in the :comment object
- Extend the entity's main GraphQL object type with a resolver like:
```elixir
field :comments_count, :integer do
    resolve(&InsightResolver.comments_count/3)
end
```
- The APIs for fetching comments will automatically start supporting the new entity
  just by adding the new types to the types file.

6. Add tests
- Create a test file similar to `dashboard_comment_api_test.exs`
