# TODO: Drop tables of removed features

The code for these features was removed, but their database tables were left
in place. Write a migration to drop them once the checks below are done.

Before writing the migration, check on prod whether the tables hold data that
should be archived first:

```sql
SELECT count(*) FROM menus;
SELECT count(*) FROM menu_items;
```

## Menus

Removed together with the `getMenu`, `createMenu`, `updateMenu`, `deleteMenu`,
`createMenuItem`, `updateMenuItem` and `deleteMenuItem` GraphQL APIs.

- Tables: `menu_items`, `menus` (drop `menu_items` first, it references `menus`)
- Created in `20231110093800_create_menus_table.exs`
- All foreign keys are `ON DELETE CASCADE`, so the leftover tables do not block
  deleting users, queries or dashboards.
