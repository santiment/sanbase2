defmodule Sanbase.Insight.PostAdmin do
  import Ecto.Query

  def custom_index_query(_conn, _schema, query) do
    from(r in query, preload: [:user])
  end

  def index(_) do
    [
      id: nil,
      title: nil,
      is_featured: nil,
      is_pulse: nil,
      state: nil,
      ready_state: nil,
      moderation_comment: nil,
      user_id: %{
        value: fn p ->
          user = Sanbase.Accounts.get_user!(p.user_id)
          user.email || user.username
        end
      }
    ]
  end
end
