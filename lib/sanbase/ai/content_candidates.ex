defmodule Sanbase.AI.ContentCandidates do
  @moduledoc ~s"""
  Read/write helpers for the admin AI-description LiveView. Encapsulates the
  raw Ecto queries against Insight, Chart.Configuration, UserList, and User so
  the LiveView never touches `Sanbase.Repo` or the underlying schemas directly.
  """

  import Ecto.Query

  alias Sanbase.Accounts.User
  alias Sanbase.Chart.Configuration
  alias Sanbase.Insight.Post
  alias Sanbase.Repo
  alias Sanbase.UserList

  @type entity_type :: :insights | :charts | :screeners | :watchlists

  @doc ~s"""
  Page of entities of `type` for `user_id` plus the total count.
  """
  @spec list(entity_type(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {list(), non_neg_integer()}
  def list(type, user_id, page, page_size) do
    offset = (page - 1) * page_size

    count = Repo.aggregate(count_query(type, user_id), :count, :id)

    entities =
      list_query(type, user_id)
      |> limit(^page_size)
      |> offset(^offset)
      |> Repo.all()

    {entities, count}
  end

  @doc ~s"""
  IDs of entities of `type` for `user_id` that still need an AI description,
  returned as `{id, type}` pairs ready for the DescriptionJob queue.
  """
  @spec pending_ids(entity_type(), non_neg_integer()) :: [{non_neg_integer(), entity_type()}]
  def pending_ids(type, user_id) do
    type
    |> pending_ids_query(user_id)
    |> Repo.all()
    |> Enum.map(&{&1, type})
  end

  @doc ~s"""
  Total count of (non-deleted) entities of `type` for `user_id`.
  """
  @spec count(entity_type(), non_neg_integer()) :: non_neg_integer()
  def count(type, user_id) do
    Repo.aggregate(count_query(type, user_id), :count, :id)
  end

  @doc ~s"""
  Copy `ai_description` over the canonical description field for every
  non-deleted entity of `type` owned by `user_id`. Returns `{rows_updated, nil}`.
  """
  @spec override_descriptions(entity_type(), non_neg_integer()) :: {non_neg_integer(), nil}
  def override_descriptions(:insights, user_id) do
    Repo.update_all(
      from(p in Post,
        where: p.user_id == ^user_id and p.is_deleted == false and not is_nil(p.ai_description),
        update: [set: [short_desc: p.ai_description]]
      ),
      []
    )
  end

  def override_descriptions(:charts, user_id) do
    Repo.update_all(
      from(c in Configuration,
        where: c.user_id == ^user_id and c.is_deleted == false and not is_nil(c.ai_description),
        update: [set: [description: c.ai_description]]
      ),
      []
    )
  end

  def override_descriptions(type, user_id) when type in [:screeners, :watchlists] do
    screener_flag = type == :screeners

    Repo.update_all(
      from(ul in UserList,
        where:
          ul.user_id == ^user_id and ul.is_deleted == false and ul.is_screener == ^screener_flag and
            not is_nil(ul.ai_description),
        update: [set: [description: ul.ai_description]]
      ),
      []
    )
  end

  @doc ~s"""
  Search users by numeric ID, or by partial case-insensitive match against
  username/email. Returns at most 10 results.
  """
  @spec search_users(String.t()) :: [User.t()]
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

  @doc ~s"""
  Fetch a user by ID, or `nil` if no such user exists.
  """
  @spec get_user(non_neg_integer()) :: User.t() | nil
  def get_user(user_id), do: Repo.get(User, user_id)

  # Private queries

  defp list_query(:insights, user_id) do
    from(p in Post,
      where: p.is_deleted == false and p.user_id == ^user_id,
      preload: [:user],
      order_by: [desc: p.inserted_at]
    )
  end

  defp list_query(:charts, user_id) do
    from(c in Configuration,
      where: c.is_deleted == false and c.user_id == ^user_id,
      preload: [:user],
      order_by: [desc: c.inserted_at]
    )
  end

  defp list_query(type, user_id) when type in [:screeners, :watchlists] do
    screener_flag = type == :screeners

    from(ul in UserList,
      where:
        ul.is_deleted == false and ul.is_screener == ^screener_flag and ul.user_id == ^user_id,
      preload: [:user],
      order_by: [desc: ul.inserted_at]
    )
  end

  defp pending_ids_query(:insights, user_id) do
    from(p in Post,
      where: p.is_deleted == false and p.user_id == ^user_id and is_nil(p.ai_description),
      order_by: [desc: p.inserted_at],
      select: p.id
    )
  end

  defp pending_ids_query(:charts, user_id) do
    from(c in Configuration,
      where: c.is_deleted == false and c.user_id == ^user_id and is_nil(c.ai_description),
      order_by: [desc: c.inserted_at],
      select: c.id
    )
  end

  defp pending_ids_query(type, user_id) when type in [:screeners, :watchlists] do
    screener_flag = type == :screeners

    from(ul in UserList,
      where:
        ul.is_deleted == false and ul.is_screener == ^screener_flag and ul.user_id == ^user_id and
          is_nil(ul.ai_description),
      order_by: [desc: ul.inserted_at],
      select: ul.id
    )
  end

  defp count_query(:insights, user_id) do
    from(p in Post, where: p.is_deleted == false and p.user_id == ^user_id)
  end

  defp count_query(:charts, user_id) do
    from(c in Configuration, where: c.is_deleted == false and c.user_id == ^user_id)
  end

  defp count_query(type, user_id) when type in [:screeners, :watchlists] do
    screener_flag = type == :screeners

    from(ul in UserList,
      where:
        ul.is_deleted == false and ul.is_screener == ^screener_flag and ul.user_id == ^user_id
    )
  end
end
