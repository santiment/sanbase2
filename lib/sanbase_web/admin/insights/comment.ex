defmodule Sanbase.ExAdmin.Insight.Comment do
  use ExAdmin.Register

  register_resource Sanbase.Insight.Comment do
    action_items(only: [:show, :edit])

    action_item(:show, fn id ->
      action_item_link("Anonymize Comment", href: "/admin2/anonymize_comment/#{id}")
    end)

    action_item(:show, fn id ->
      action_item_link("Delete Subtree (Danger)", href: "/admin2/delete_subcomment_tree/#{id}")
    end)

    show _ do
      attributes_table(all: true)
    end
  end
end
