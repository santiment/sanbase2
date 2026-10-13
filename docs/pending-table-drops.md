# TODO: Drop tables of removed features

The code for these features was removed, but their database tables were left
in place. Write a migration to drop them once the checks below are done.

Before writing the migration, check on prod whether the tables hold data that
should be archived first:

```sql
SELECT count(*) FROM menus;
SELECT count(*) FROM menu_items;
SELECT count(*) FROM questionnaires;
SELECT count(*) FROM questionnaire_questions;
SELECT count(*) FROM questionnaire_answers;
```

## Menus

Removed together with the `getMenu`, `createMenu`, `updateMenu`, `deleteMenu`,
`createMenuItem`, `updateMenuItem` and `deleteMenuItem` GraphQL APIs.

- Tables: `menu_items`, `menus` (drop `menu_items` first, it references `menus`)
- Created in `20231110093800_create_menus_table.exs`
- All foreign keys are `ON DELETE CASCADE`, so the leftover tables do not block
  deleting users, queries or dashboards.

## Questionnaire

Removed together with the `getQuestionnaire`, `getQuestionnaireUserAnswers` and
all questionnaire/question/answer create, update and delete GraphQL APIs.

- Tables: `questionnaire_answers`, `questionnaire_questions`, `questionnaires`
  (drop in this order)
- Enum type: `question_type`, used only by `questionnaire_questions.type`. Not to
  be confused with the `question_type` varchar column of `question_answer_logs`,
  which is still in use.
- Created in `20230113134151_create_question_type_enum.exs`,
  `20230114134332_create_questionnaire_tables.exs`,
  `20230124105934_add_questionnaire_deleted_flag.exs`,
  `20230206085439_recreate_question_type.exs` and
  `20230206100629_add_cascade_delete_to_questionnaire.exs`
- `questionnaire_answers.user_id` references `users` without `ON DELETE
  CASCADE`, so deleting a user who has answers fails until this table is dropped.
