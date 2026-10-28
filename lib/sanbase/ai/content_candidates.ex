defmodule Sanbase.AI.ContentCandidates do
  @moduledoc "Queries behind the admin AI-description LiveView."

  import Ecto.Query

  alias Sanbase.Accounts.User
  alias Sanbase.Chart.Configuration
  alias Sanbase.Insight.Post
  alias Sanbase.Repo
  alias Sanbase.UserList

  @doc "A page of the user's entities of `type` and their total count."
  def list(type, user_id, page, page_size) do
    entities =
      base_query(type, user_id)
      |> order_by([e], desc: e.inserted_at)
      |> preload([:user])
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))
      |> Repo.all()

    {entities, count(type, user_id)}
  end

  @doc "`{id, type}` of the user's entities that have no AI description yet."
  def pending_ids(type, user_id) do
    base_query(type, user_id)
    |> where([e], is_nil(e.ai_description))
    |> order_by([e], desc: e.inserted_at)
    |> select([e], e.id)
    |> Repo.all()
    |> Enum.map(&{&1, type})
  end

  def count(type, user_id) do
    Repo.aggregate(base_query(type, user_id), :count, :id)
  end

  @doc "Replace the description of the user's entities with their AI description."
  def override_descriptions(:insights, user_id) do
    with_ai_description(:insights, user_id)
    |> update([p], set: [short_desc: p.ai_description])
    |> Repo.update_all([])
  end

  def override_descriptions(type, user_id) when type in [:charts, :screeners, :watchlists] do
    with_ai_description(type, user_id)
    |> update([e], set: [description: e.ai_description])
    |> Repo.update_all([])
  end

  @doc "Up to 10 users matching an id, or part of a username or email."
  def search_users(query) do
    query = String.trim(query)

    case Integer.parse(query) do
      {user_id, ""} ->
        Repo.all(from(u in User, where: u.id == ^user_id, limit: 10))

      _ ->
        pattern = "%#{String.downcase(query)}%"

        Repo.all(
          from(u in User,
            where:
              fragment("lower(?) LIKE ?", u.username, ^pattern) or
                fragment("lower(?) LIKE ?", u.email, ^pattern),
            order_by: u.id,
            limit: 10
          )
        )
    end
  end

  def get_user(user_id), do: Repo.get(User, user_id)

  # Every query builds on this one, so the counts always match the listed rows
  defp base_query(:insights, user_id) do
    from(p in Post, where: p.is_deleted == false and p.user_id == ^user_id)
  end

  defp base_query(:charts, user_id) do
    from(c in Configuration, where: c.is_deleted == false and c.user_id == ^user_id)
  end

  defp base_query(type, user_id) when type in [:screeners, :watchlists] do
    screener_flag = type == :screeners

    from(ul in UserList,
      where:
        ul.is_deleted == false and ul.is_screener == ^screener_flag and ul.user_id == ^user_id
    )
  end

  defp with_ai_description(type, user_id) do
    base_query(type, user_id)
    |> where([e], not is_nil(e.ai_description))
  end
end
