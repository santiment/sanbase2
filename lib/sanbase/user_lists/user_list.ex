defmodule Sanbase.UserList do
  @moduledoc ~s"""
  Module for working with lists of projects.

  A watchlist (or user list) is a user created list of projects. The projects
  in the list can be some concrete projects, they can be dynamically determined
  by a function or the combination of both.

  The list of some concrete slugs is used when a user wants to create a list of
  projects they are interested in. It can contain any project.

  The watchlist defined by a function is being used when a watchlist can change
  frequently according to some rules. Examples for such lists are having a watchlist
  of the top 50 ERC20 projects or all projects with a market segment "stablecoin"
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query
  import Sanbase.UserList.EventEmitter, only: [emit_event: 3]

  alias Sanbase.Accounts.User
  alias Sanbase.UserList.ListItem
  alias Sanbase.WatchlistFunction
  alias Sanbase.Repo
  alias Sanbase.Timeline.TimelineEvent
  alias Sanbase.BlockchainAddress.BlockchainAddressUserPair

  schema "user_lists" do
    field(:type, WatchlistType, default: :project)

    field(:color, ColorEnum, default: :none)
    field(:description, :string)
    field(:function, WatchlistFunction, default: %WatchlistFunction{})
    field(:is_monitored, :boolean, default: false)
    field(:is_public, :boolean, default: false)
    field(:is_screener, :boolean, default: false)
    field(:name, :string)
    field(:slug, :string)

    belongs_to(:user, User)
    belongs_to(:table_configuration, Sanbase.TableConfiguration)

    has_one(:featured_item, Sanbase.FeaturedItem, on_delete: :delete_all)

    has_many(:projects, ListItem, on_delete: :delete_all)
    has_many(:blockchain_addresses, ListItem, on_delete: :delete_all)

    has_many(:list_items, ListItem, on_delete: :delete_all, on_replace: :delete)
    has_many(:timeline_events, TimelineEvent, on_delete: :delete_all)

    timestamps()
  end

  # ex_admin needs changeset function
  def changeset(user_list, attrs \\ %{}) do
    update_changeset(user_list, attrs)
  end

  @create_update_fields [:color, :description, :function, :is_monitored, :is_public, :is_screener] ++
                          [:name, :slug, :table_configuration_id, :type, :user_id]
  def create_changeset(%__MODULE__{} = user_list, attrs \\ %{}) do
    user_list
    |> cast(attrs, @create_update_fields)
    |> validate_required([:name, :user_id])
    |> validate_change(:function, &validate_function/2)
    |> unique_constraint(:slug)
  end

  def update_changeset(%__MODULE__{id: _id} = user_list, attrs \\ %{}) do
    user_list
    |> cast(attrs, @create_update_fields)
    |> cast_assoc(:list_items)
    |> validate_change(:function, &validate_function/2)
    |> unique_constraint(:slug)
  end

  defp validate_function(_changeset, nil), do: []

  defp validate_function(_changeset, function) do
    {:ok, function} = function |> WatchlistFunction.cast()

    case WatchlistFunction.valid_function?(function) do
      true -> []
      {:error, error} -> [function: "Provided watchlist function is not valid. Reason: #{error}"]
    end
  end

  def by_id(id) do
    from(ul in __MODULE__, where: ul.id == ^id)
    |> Repo.one()
    |> case do
      nil -> {:error, "Watchlist with #{id} does not exist."}
      watchlist -> {:ok, watchlist}
    end
  end

  def by_id!(id) do
    by_id(id)
    |> case do
      {:ok, watchlist} -> watchlist
      {:error, error} -> raise(error)
    end
  end

  def by_slug(slug) when is_binary(slug) do
    from(ul in __MODULE__, where: ul.slug == ^slug)
    |> Repo.one()
  end

  def is_public?(%__MODULE__{is_public: is_public}), do: is_public
  def is_screener?(%__MODULE__{is_screener: is_screener}), do: is_screener

  @doc ~s"""
  Return a list of all blockchain addresses in a watchlist.
  """
  def get_blockchain_addresses(%__MODULE__{function: function} = watchlist) do
    case WatchlistFunction.evaluate(function) do
      {:error, error} ->
        {:error, error}

      {:ok, %{blockchain_addresses: blockchain_addresses}} ->
        list_item_blockchain_addresses = ListItem.get_blockchain_addresses(watchlist)

        blockchain_addresses =
          blockchain_addresses
          |> Enum.map(fn %{address: address, infrastructure: infrastructure} ->
            %{
              id: nil,
              labels: [],
              notes: "",
              blockchain_address: %{
                address: address,
                infrastructure: %{code: infrastructure}
              }
            }
          end)

        # keep the list items in the first places so they will be taken with
        # higher priority in order to keep the notes and labels
        unique_blockchain_addresses =
          (list_item_blockchain_addresses ++ blockchain_addresses)
          |> Enum.uniq_by(&{&1.blockchain_address.address, &1.blockchain_address.infrastructure})

        {:ok,
         %{
           blockchain_addresses: unique_blockchain_addresses,
           total_blockchain_addresses_count: length(unique_blockchain_addresses)
         }}
    end
  end

  @doc ~s"""
  Return a list of all projects in a watchlist.
  """
  def get_projects(%__MODULE__{function: function} = watchlist) do
    case WatchlistFunction.evaluate(function) do
      {:error, error} ->
        {:error, error}

      # If there is pagination, the total number of projects cannot be properly
      # defined without having all the slugs, including the ones from the other pages
      {:ok, %{projects: projects, has_pagination?: true, all_included_slugs: all_included_slugs}} ->
        list_item_projects = ListItem.get_projects(watchlist)

        unique_projects =
          (projects ++ list_item_projects)
          |> Enum.reject(&is_nil(&1.slug))
          |> Enum.uniq_by(& &1.id)

        total_projects_count =
          (Enum.map(list_item_projects, & &1.slug) ++ all_included_slugs)
          |> Enum.reject(&is_nil(&1.slug))
          |> Enum.uniq_by(& &1.id)
          |> length()

        {:ok, %{projects: unique_projects, total_projects_count: total_projects_count}}

      {:ok, %{projects: projects}} ->
        list_item_projects = ListItem.get_projects(watchlist)

        unique_projects =
          (projects ++ list_item_projects)
          |> Enum.reject(&is_nil(&1.slug))
          |> Enum.uniq_by(& &1.id)

        {:ok, %{projects: unique_projects, total_projects_count: length(unique_projects)}}
    end
  end

  def get_slugs(%__MODULE__{function: _} = watchlist) do
    case get_projects(watchlist) do
      {:ok, %{projects: projects}} ->
        {:ok, Enum.map(projects, & &1.slug)}

      {:error, error} ->
        {:error, error}
    end
  end

  def create_user_list(%User{id: user_id} = user, params \\ %{}) do
    params = params |> Map.put(:user_id, user_id)

    %__MODULE__{}
    |> create_changeset(params)
    |> Repo.insert()
    |> emit_event(:create_watchlist, %{})
    |> case do
      {:ok, user_list} ->
        case list_items = Map.get(params, :list_items) do
          nil -> {:ok, user_list}
          _ -> update_user_list(user, %{id: user_list.id, list_items: list_items})
        end

      {:error, error} ->
        {:error, error}
    end
  end

  def update_user_list(user, params) do
    %{id: user_list_id} = params
    params = update_list_items_params(params, user)

    changeset =
      user_list_id
      |> by_id!()
      |> Repo.preload(:list_items)
      |> update_changeset(params)

    Repo.update(changeset)
    |> maybe_create_event(changeset, TimelineEvent.update_watchlist_type())
  end

  def add_user_list_items(user, %{id: id, list_items: _} = params) do
    %{list_items: list_items} = update_list_items_params(params, user)

    case ListItem.create(list_items) do
      {:ok, _} -> by_id(id)
      {:error, error} -> {:error, error}
    end
  end

  def remove_user_list_items(user, %{id: id, list_items: _} = params) do
    %{list_items: list_items} = update_list_items_params(params, user)

    case ListItem.delete(list_items) do
      {nil, _} -> by_id(id)
      {num, _} when is_integer(num) -> by_id(id)
      {:error, error} -> {:error, error}
    end
  end

  def remove_user_list(_user, %{id: id}) do
    by_id!(id)
    |> Repo.delete()
    |> emit_event(:delete_watchlist, %{})
  end

  def fetch_user_lists(%User{id: user_id}, type) do
    result =
      __MODULE__
      |> filter_by_user_id_query(user_id)
      |> filter_by_type_query(type)
      |> Repo.all()

    {:ok, result}
  end

  def fetch_public_user_lists(%User{id: user_id}, type) do
    result =
      __MODULE__
      |> filter_by_user_id_query(user_id)
      |> filter_by_is_public_query(true)
      |> filter_by_type_query(type)
      |> Repo.all()

    {:ok, result}
  end

  def fetch_all_public_lists(type) do
    result =
      __MODULE__
      |> filter_by_is_public_query(true)
      |> filter_by_type_query(type)
      |> Repo.all()

    {:ok, result}
  end

  def user_list(user_list_id, user) do
    query = user_list_query_by_user_id(user)
    {:ok, Repo.get(query, user_list_id)}
  end

  def user_list_by_slug(slug, user) do
    query = user_list_query_by_user_id(user)
    {:ok, Repo.get_by(query, slug: slug)}
  end

  # Private functions

  defp maybe_create_event({:ok, watchlist}, changeset, event_type) do
    TimelineEvent.maybe_create_event_async(event_type, watchlist, changeset)
    {:ok, watchlist}
  end

  defp maybe_create_event(error_result, _, _), do: error_result

  defp user_list_query_by_user_id(%User{id: user_id}) when is_integer(user_id) and user_id > 0 do
    from(ul in __MODULE__, where: ul.is_public == true or ul.user_id == ^user_id)
  end

  defp user_list_query_by_user_id(_) do
    from(ul in __MODULE__, where: ul.is_public == true)
  end

  defp update_list_items_params(%{list_items: [%{project_id: _} | _]} = params, _user) do
    %{id: user_list_id, list_items: input_objects} = params

    list_items =
      input_objects
      |> Enum.map(fn item -> %{project_id: item.project_id, user_list_id: user_list_id} end)
      |> Enum.uniq_by(& &1.project_id)

    %{params | list_items: list_items}
  end

  defp update_list_items_params(
         %{list_items: [%{blockchain_address: _} | _]} = params,
         user
       ) do
    %{id: user_list_id, list_items: input_objects} = params

    # A list of list item input objects in the form of maps
    input_blockchain_addresses =
      input_objects
      |> Enum.map(& &1.blockchain_address)
      |> Enum.uniq_by(& &1.address)

    # A list of Sanbase.BlockchainAddressUserPair structs
    {:ok, blockchain_address_user_pairs} =
      get_or_create_blockchain_address_user_pairs(input_blockchain_addresses, user)

    list_items =
      blockchain_address_user_pairs
      |> Enum.map(fn pair ->
        %{
          blockchain_address_user_pair_id: pair.id,
          user_list_id: user_list_id
        }
      end)

    %{params | list_items: list_items}
  end

  defp update_list_items_params(params, _user) when is_map(params), do: params

  defp filter_by_user_id_query(query, user_id) do
    query
    |> where([ul], ul.user_id == ^user_id)
  end

  defp filter_by_type_query(query, type) do
    query
    |> where([ul], ul.type == ^type)
  end

  defp filter_by_is_public_query(query, is_public) do
    query
    |> where([ul], ul.is_public == ^is_public)
  end

  defp get_or_create_blockchain_address_user_pairs(input_blockchain_addresses, user) do
    blockchain_address_to_id_map = blockchain_address_to_id_map(input_blockchain_addresses)

    input_blockchain_addresses
    |> Enum.map(fn %{address: address} = addr ->
      %{
        blockchain_address_id: Map.get(blockchain_address_to_id_map, address),
        user_id: user.id,
        labels: Map.get(addr, :labels),
        notes: Map.get(addr, :notes)
      }
    end)
    |> BlockchainAddressUserPair.maybe_create()
  end

  defp blockchain_address_to_id_map(input_blockchain_addresses) do
    # A list map in the format %{"ETH" => 1, "BTC" => 2, "XRP" => 3}
    infr_code_to_id_map =
      input_blockchain_addresses
      |> Enum.reduce(MapSet.new(), &MapSet.put(&2, &1.infrastructure))
      |> Enum.to_list()
      |> Sanbase.Model.Infrastructure.by_codes()
      |> Map.new(fn %{id: id, code: code} -> {code, id} end)

    # A list of Sanbase.BlockchainAddress structs
    {:ok, blockchain_addresses} =
      input_blockchain_addresses
      |> Enum.map(fn addr ->
        %{
          address: addr.address,
          infrastructure_id: Map.get(infr_code_to_id_map, addr.infrastructure)
        }
      end)
      |> Sanbase.BlockchainAddress.maybe_create()

    blockchain_addresses
    |> Map.new(fn %{address: address, id: id} -> {address, id} end)
  end
end
