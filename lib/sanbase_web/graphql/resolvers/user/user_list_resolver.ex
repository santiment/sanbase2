defmodule SanbaseWeb.Graphql.Resolvers.UserListResolver do
  require Logger

  import Absinthe.Resolution.Helpers, except: [async: 1]
  import SanbaseWeb.Graphql.Helpers.Async, only: [async: 1]
  import Sanbase.Utils.ErrorHandling, only: [changeset_errors: 1]

  alias Sanbase.Accounts.User
  alias Sanbase.UserList
  alias Sanbase.Project
  alias Sanbase.SocialData.TrendingWords

  alias SanbaseWeb.Graphql.Helpers.Utils
  alias SanbaseWeb.Graphql.Cache
  alias SanbaseWeb.Graphql.SanbaseDataloader

  @trending_words_size 10
  @trending_fields [:trending_slugs, :trending_tickers, :trending_names, :trending_projects]
                   |> Enum.map(&Inflex.camelize(&1, :lower))

  ###########################
  #         Queries         #
  ###########################

  def fetch_user_lists(_root, %{} = args, %{context: %{auth: %{current_user: current_user}}}) do
    type = Map.get(args, :type) || :project
    UserList.fetch_user_lists(current_user, type)
  end

  def fetch_user_lists(_root, _args, _resolution) do
    {:error, "Only logged in users can call this method"}
  end

  def fetch_public_user_lists(_root, %{} = args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    type = Map.get(args, :type) || :project
    UserList.fetch_public_user_lists(current_user, type)
  end

  def fetch_all_public_user_lists(_root, %{} = args, _resolution) do
    type = Map.get(args, :type) || :project
    UserList.fetch_all_public_lists(type)
  end

  # def dynamic_watchlist(_root, %{} = args, _resolution) do
  #   projects_selector = Map.get(args, :projects_selector)
  #   blockchain_addresses_selector = Map.get(args, :blockchain_addresses_selector)

  #   with %{} = fun <- Sanbase.WatchlistFunction.new(selector),
  #        {:ok, result} <- Sanbase.WatchlistFunction.evaluate(fun) do
  #     {:ok, result}
  #   end
  # end

  def watchlist(_root, %{id: id}, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    Process.put(:do_not_cache_query, true)
    UserList.user_list(id, current_user)
  end

  def watchlist(_root, %{id: id}, _resolution) do
    Process.put(:do_not_cache_query, true)
    UserList.user_list(id, %User{id: nil})
  end

  def watchlist_by_slug(_root, %{slug: slug}, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    Process.put(:do_not_cache_query, true)
    UserList.user_list_by_slug(slug, current_user)
  end

  def watchlist_by_slug(_root, %{slug: slug}, _resolution) do
    Process.put(:do_not_cache_query, true)
    UserList.user_list_by_slug(slug, %User{id: nil})
  end

  def public_watchlists(%User{} = user, %{} = args, _resolution) do
    type = Map.get(args, :type) || :project
    UserList.fetch_public_user_lists(user, type)
  end

  def watchlists(%User{} = user, %{} = args, _resolution) do
    type = Map.get(args, :type) || :project
    UserList.fetch_user_lists(user, type)
  end

  def user_list(_root, %{user_list_id: user_list_id}, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    UserList.user_list(user_list_id, current_user)
  end

  def user_list(_root, %{user_list_id: user_list_id}, _resolution) do
    UserList.user_list(user_list_id, %User{id: nil})
  end

  def settings(%UserList{} = watchlist, _args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    UserList.Settings.settings_for(watchlist, current_user)
  end

  def settings(%UserList{} = watchlist, _args, _) do
    UserList.Settings.settings_for(watchlist, nil)
  end

  def stats(
        %UserList{type: :project} = user_list,
        _args,
        resolution
      ) do
    with {:ok, %{projects: projects}} <- UserList.get_projects(user_list) do
      trending_words_stats = trending_words_stats(projects, resolution)
      result = Map.merge(trending_words_stats, %{projects_count: length(projects)})
      {:ok, result}
    end
  end

  def stats(
        %UserList{type: :blockchain_address} = user_list,
        _args,
        _resolution
      ) do
    with {:ok, %{total_blockchain_addresses_count: count}} <-
           UserList.get_blockchain_addresses(user_list) do
      {:ok, %{blockchain_addresses_count: count}}
    end
  end

  def comments_count(%{id: id}, _args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :watchlist_comments_count, id)
    |> on_load(fn loader ->
      count = Dataloader.get(loader, SanbaseDataloader, :watchlist_comments_count, id)
      {:ok, count || 0}
    end)
  end

  # Private functions

  defp trending_words_stats(projects, resolution) do
    requested_trending_fields =
      MapSet.intersection(Utils.requested_fields(resolution), MapSet.new(@trending_fields))

    if Enum.empty?(requested_trending_fields) do
      %{}
    else
      get_trending_words_stats(projects)
    end
  end

  defp get_trending_words_stats(projects) do
    {:ok, trending_words} =
      Cache.wrap(
        fn ->
          {:ok, words} = TrendingWords.get_currently_trending_words(@trending_words_size, :all)

          result =
            words
            |> Enum.map(fn %{word: word} -> String.downcase(word) end)
            |> MapSet.new()

          {:ok, result}
        end,
        :currently_trending_words,
        %{size: @trending_words_size}
      ).()

    {tickers, slugs, names} =
      Enum.reduce(projects, {[], [], []}, fn proj, {tickers, slugs, names} ->
        {
          [String.downcase(proj.ticker) | tickers],
          [String.downcase(proj.slug) | slugs],
          [String.downcase(proj.name) | names]
        }
      end)

    tickers_set = MapSet.new(tickers)
    slugs_set = MapSet.new(slugs)
    names_set = MapSet.new(names)

    trending_assets =
      tickers_set
      |> MapSet.union(slugs_set)
      |> MapSet.union(names_set)
      |> MapSet.intersection(trending_words)

    trending_projects =
      trending_assets
      |> Enum.to_list()
      |> Project.List.by_name_ticker_slug()

    %{
      trending_tickers: Enum.filter(trending_words, &Enum.member?(tickers_set, &1)),
      trending_slugs: Enum.filter(trending_words, &Enum.member?(slugs_set, &1)),
      trending_names: Enum.filter(trending_words, &Enum.member?(names_set, &1)),
      trending_projects: trending_projects
    }
  end

  def historical_stats(
        %UserList{} = user_list,
        %{from: from, to: to, interval: interval},
        _resolution
      ) do
    async(fn ->
      with {:ok, %{projects: projects}} <- UserList.get_projects(user_list),
           slugs when is_list(slugs) <- Enum.map(projects, & &1.slug),
           {:ok, result} <- Sanbase.Price.combined_marketcap_and_volume(slugs, from, to, interval) do
        {:ok, result}
      else
        {:error, error} ->
          {:error, "Can't fetch historical stats for a watchlist. Reason: #{inspect(error)}"}

        _ ->
          {:error, "Can't fetch historical stats for a watchlist."}
      end
    end)
  end

  def list_items(%UserList{type: :project} = user_list, _args, _resolution) do
    async(fn ->
      case UserList.get_projects(user_list) do
        {:ok, %{projects: projects}} ->
          result =
            projects
            |> Project.preload_assocs()
            |> Enum.map(&%{project: &1})

          {:ok, result}

        {:error, error} ->
          {:error, error}
      end
    end)
  end

  def list_items(%UserList{type: :blockchain_address} = user_list, _args, _resolution) do
    async(fn ->
      {:ok, %{blockchain_addresses: blockchain_addresses}} =
        UserList.get_blockchain_addresses(user_list)

      result =
        blockchain_addresses
        |> Enum.map(
          &%{
            blockchain_address: %{
              id: &1.id,
              address: &1.blockchain_address.address,
              labels: &1.labels,
              notes: &1.notes,
              infrastructure: &1.blockchain_address.infrastructure.code
            }
          }
        )

      {:ok, result}
    end)
  end

  ###########################
  #        Mutations        #
  ###########################

  def create_user_list(_root, args, %{context: %{auth: %{current_user: current_user}}}) do
    with {:ok, args} <- transform_slug_to_project_id(args) do
      case UserList.create_user_list(current_user, args) do
        {:ok, user_list} ->
          {:ok, user_list}

        {:error, changeset} ->
          {
            :error,
            message: "Cannot create user list", details: changeset_errors(changeset)
          }
      end
    end
  end

  def update_watchlist(_root, %{id: id} = args, %{context: %{auth: %{current_user: current_user}}}) do
    with {:ok, watchlist} <- UserList.by_id(id, []),
         true <- has_permissions?(watchlist, current_user, :update),
         {:ok, args} <- transform_slug_to_project_id(args) do
      case UserList.update_user_list(current_user, args) do
        {:ok, user_list} ->
          {:ok, user_list}

        {:error, changeset} ->
          {
            :error,
            message: "Cannot update user list", details: changeset_errors(changeset)
          }
      end
    end
  end

  def add_watchlist_items(
        _root,
        %{id: id, list_items: _} = args,
        %{context: %{auth: %{current_user: current_user}}}
      ) do
    with {:ok, watchlist} <- UserList.by_id(id, []),
         {:ok, args} <- transform_slug_to_project_id(args),
         true <- has_permissions?(watchlist, current_user, :update) do
      case UserList.add_user_list_items(current_user, args) do
        {:ok, user_list} ->
          {:ok, user_list}

        {:error, changeset} ->
          {
            :error,
            message: "Cannot add items to a watchlist", details: changeset_errors(changeset)
          }
      end
    end
  end

  def remove_watchlist_items(
        _root,
        %{id: id, list_items: _} = args,
        %{context: %{auth: %{current_user: current_user}}}
      ) do
    with {:ok, watchlist} <- UserList.by_id(id, []),
         {:ok, args} <- transform_slug_to_project_id(args),
         true <- has_permissions?(watchlist, current_user, :update) do
      case UserList.remove_user_list_items(current_user, args) do
        {:ok, user_list} ->
          {:ok, user_list}

        {:error, changeset} ->
          {
            :error,
            message: "Cannot remove items from a watchlist", details: changeset_errors(changeset)
          }
      end
    end
  end

  defp transform_slug_to_project_id(%{list_items: list_items} = args) do
    {slug_items, non_slug_items} = Enum.split_with(list_items, &Map.has_key?(&1, :slug))

    slugs = Enum.map(slug_items, &(&1[:slug] || &1["slug"]))

    project_items =
      Project.List.ids_by_slugs(slugs)
      |> Enum.map(fn project_id -> %{project_id: project_id} end)

    list_items = non_slug_items ++ project_items

    args = %{args | list_items: list_items}
    {:ok, args}
  end

  defp transform_slug_to_project_id(args), do: {:ok, args}

  def update_watchlist_settings(_root, %{id: watchlist_id, settings: settings}, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    UserList.Settings.update_or_create_settings(watchlist_id, current_user.id, settings)
    |> case do
      {:ok, %{settings: settings}} ->
        {:ok, settings}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error,
         message: "Cannot update watchlist settings", details: changeset_errors(changeset)}
    end
  end

  def remove_user_list(_root, %{id: watchlist_id} = args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    with {:ok, watchlist} <- UserList.by_id(watchlist_id, []),
         true <- has_permissions?(watchlist, current_user, :delete),
         {:ok, watchlist} <- remove_watchlist(current_user, args) do
      {:ok, watchlist}
    end
  end

  # Private functions

  defp has_permissions?(watchlist, %User{id: user_id}, action) do
    case watchlist do
      %UserList{user_id: ^user_id} -> true
      _ -> {:error, "Cannot #{action} watchlist belonging to another user"}
    end
  end

  defp remove_watchlist(current_user, args) do
    case UserList.remove_user_list(current_user, args) do
      {:ok, watchlist} ->
        {:ok, watchlist}

      {:error, changeset} ->
        {
          :error,
          message: "Cannot remove watchlist", details: changeset_errors(changeset)
        }
    end
  end
end
