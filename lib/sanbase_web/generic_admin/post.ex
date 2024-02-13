defmodule SanbaseWeb.GenericAdmin.Post do
  alias Sanbase.Insight.Post
  def schema_module, do: Post

  def resource do
    %{
      preloads: [:user, :price_chart_project],
      index_fields: [
        :id,
        :title,
        :is_featured,
        :is_pulse,
        :state,
        :ready_state,
        :moderation_comment,
        :user_id
      ],
      edit_fields: [
        :is_featured,
        :is_pulse,
        :is_paywall_required,
        :ready_state,
        :prediction,
        :state,
        :moderation_comment
      ],
      field_types: %{
        moderation_comment: :text
      },
      collections: %{
        state:
          [
            Post.awaiting_approval_state(),
            Post.approved_state(),
            Post.declined_state()
          ]
          |> Enum.map(&{&1, &1})
      },
      funcs: %{
        user_id: &SanbaseWeb.GenericAdmin.User.user_link/1
      }
    }
  end
end

defmodule SanbaseWeb.GenericAdmin.PostTags do
  def schema_module, do: Sanbase.Insight.PostTag

  def resource do
    %{}
  end
end
