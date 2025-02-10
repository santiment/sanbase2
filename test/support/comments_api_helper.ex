defmodule SanbaseWeb.CommentsApiHelper do
  @moduledoc false
  import SanbaseWeb.Graphql.TestHelpers

  def create_comment(conn, entity_id, content, opts \\ []) do
    mutation = create_comment_mutation(entity_id, content, opts)
    execute_mutation(conn, mutation, "createComment")
  end

  def create_comment_with_error(conn, entity_id, content, opts \\ []) do
    mutation = create_comment_mutation(entity_id, content, opts)
    execute_mutation_with_error(conn, mutation)
  end

  def update_comment(conn, comment_id, content, opts \\ []) do
    extra_fields_str =
      opts
      |> Keyword.get(:extra_fields, [])
      |> Enum.join("\n")

    mutation = """
    mutation {
      updateComment(
        commentId: #{comment_id}
        content: "#{content}") {
          id
          content
          user{ id username email }
          subcommentsCount
          insertedAt
          editedAt
          #{extra_fields_str}
      }
    }
    """

    execute_mutation(conn, mutation, "updateComment")
  end

  def delete_comment(conn, comment_id, opts \\ []) do
    extra_fields_str =
      opts
      |> Keyword.get(:extra_fields, [])
      |> Enum.join("\n")

    mutation = """
    mutation {
      deleteComment(commentId: #{comment_id}) {
        id
        content
        user{ id username email }
        subcommentsCount
        insertedAt
        editedAt
        #{extra_fields_str}
      }
    }
    """

    execute_mutation(conn, mutation, "deleteComment")
  end

  def get_comments(conn, entity_id, opts \\ []) do
    entity_type = Keyword.fetch!(opts, :entity_type)
    entity_type = entity_type |> to_string() |> String.upcase()

    extra_fields_str =
      opts
      |> Keyword.get(:extra_fields, [])
      |> Enum.join("\n")

    query = """
    {
      comments(
        entityType: #{entity_type}
        id: #{entity_id}
        cursor: {type: BEFORE, datetime: "#{DateTime.utc_now()}"}) {
          id
          content
          parentId
          rootParentId
          user{ id username email }
          subcommentsCount
          #{extra_fields_str}
      }
    }
    """

    execute_query(conn, query, "comments")
  end

  defp create_comment_mutation(entity_id, content, opts) do
    entity_type = Keyword.fetch!(opts, :entity_type)
    entity_type = entity_type |> to_string() |> String.upcase()
    parent_id = Keyword.get(opts, :parent_id, nil)

    extra_fields_str =
      opts
      |> Keyword.get(:extra_fields, [])
      |> Enum.join("\n")

    """
    mutation {
      createComment(
        entityType: #{entity_type}
        id: #{entity_id}
        parentId: #{parent_id || "null"}
        content: "#{content}") {
          id
          content
          user{ id username email }
          subcommentsCount
          insertedAt
          editedAt
          #{extra_fields_str}
      }
    }
    """
  end
end
