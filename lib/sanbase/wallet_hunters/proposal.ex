defmodule Sanbase.WalletHunters.Proposal do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query
  import Sanbase.SmartContracts.Utils

  alias Sanbase.Repo
  alias Sanbase.Accounts.{User, EthAccount}
  alias Sanbase.WalletHunters.{Contract, Bounty}
  alias Sanbase.WalletHunters.{RelayerApi, RelayQuota}

  @states_map %{
    0 => :active,
    1 => :approved,
    2 => :declined,
    3 => :discarded
  }

  # Polling for transaction 100 times at 5s interval
  @retries_num 100
  @sleep_time 5000

  schema "wallet_hunters_proposals" do
    field(:hunter_address, :string)
    field(:proposal_id, :integer)
    field(:transaction_id, :string)
    field(:transaction_status, :string, default: "pending")
    field(:text, :string)
    field(:title, :string)

    field(:proposed_address, :string)
    field(:user_labels, {:array, :string}, default: [])

    belongs_to(:user, User)
    belongs_to(:bounty, Bounty)

    timestamps()
  end

  @doc false
  def changeset(proposal, attrs) do
    proposal
    |> cast(attrs, [
      :title,
      :text,
      :proposal_id,
      :transaction_id,
      :hunter_address,
      :user_id,
      :proposed_address,
      :user_labels,
      :transaction_status,
      :bounty_id
    ])
    |> validate_required([
      :transaction_id,
      :transaction_status,
      :title,
      :text,
      :hunter_address,
      :proposed_address
    ])
    |> normalize_text(:text, attrs[:text])
    |> validate_change(:hunter_address, &validate_address/2)
    |> validate_change(:proposed_address, &validate_address/2)
    |> unique_constraint(:proposal_id)
    |> unique_constraint(:transaction_id)
  end

  def sanitize_markdown(markdown) do
    # mark lines that start with "> " (valid markdown blockquote syntax)
    markdown = Regex.replace(~r/^>\s+([^\s+])/m, markdown, "REPLACED_BLOCKQUOTE\\1")
    markdown = HtmlSanitizeEx.markdown_html(markdown)
    # Bring back the blockquotes
    Regex.replace(~r/^REPLACED_BLOCKQUOTE/m, markdown, "> ")
  end

  def poll_pending_transactions() do
    from(p in __MODULE__, where: p.transaction_status == "pending")
    |> Repo.all()
    |> Enum.each(fn %{transaction_id: transaction_id} ->
      poll_transaction_and_maybe_update(transaction_id)
    end)
  end

  def update_earned_relays() do
    proposals =
      Contract.wallet_proposals()
      |> map_response()
      |> merge_db_proposals()

    proposals
    |> Enum.group_by(& &1.user_id)
    |> Enum.each(fn {user_id, proposals_per_user} ->
      Enum.filter(proposals_per_user, &(&1.state == :approved))
      |> length()
      |> case do
        approved when approved > 0 ->
          :ok
          RelayQuota.update_earned_proposals(user_id, approved)

        _ ->
          :ok
      end
    end)
  end

  def create_proposal(%{request: request, signature: signature} = args) do
    with true <- RelayQuota.can_relay?(args.user_id),
         {:ok, %{"hash" => transaction_id}} <- RelayerApi.relay(request, signature),
         {:ok, proposal} <- create_db_proposal(Map.put(args, :transaction_id, transaction_id)),
         {:ok, _} <- RelayQuota.create_or_update(args.user_id) do
      async_poll_transaction_status(transaction_id)
      {:ok, proposal}
    end
  end

  def create_proposal(%{transaction_id: transaction_id} = args) do
    with {:ok, proposal} <- create_db_proposal(args) do
      async_poll_transaction_status(transaction_id)
      {:ok, proposal}
    end
  end

  def create_db_proposal(args) do
    args =
      args
      |> Map.update!(:hunter_address, &String.downcase/1)
      |> Map.update!(:proposed_address, &String.downcase/1)
      |> maybe_add_user()

    changeset(%__MODULE__{}, args)
    |> Repo.insert()
    |> preload()
  end

  def update_db_proposal(proposal, args) do
    proposal
    |> changeset(args)
    |> Repo.update()
    |> preload()
  end

  def fetch_by_transaction_id(transaction_id) do
    Repo.get_by(__MODULE__, transaction_id: transaction_id)
  end

  def create(args) do
    args =
      args
      |> Map.update!(:hunter_address, &String.downcase/1)
      |> Map.update!(:proposed_address, &String.downcase/1)
      |> maybe_add_user()

    with proposal <- Contract.wallet_proposal(args.proposal_id),
         {:ok, db_proposal} <- changeset(%__MODULE__{}, args) |> Repo.insert() do
      db_proposal = Repo.preload(db_proposal, :user) |> Map.from_struct()

      response =
        proposal
        |> List.wrap()
        |> map_response()
        |> hd()
        |> Map.merge(db_proposal)

      {:ok, response}
    end
  end

  def fetch_by_proposal_id(proposal_id) do
    with proposal <- Contract.wallet_proposal(proposal_id) do
      proposal
      |> List.wrap()
      |> map_response()
      |> merge_db_proposals()
      |> case do
        [] -> {:error, "No proposal with id #{proposal_id} found."}
        [proposal | _] -> {:ok, proposal}
      end
    end
  end

  def fetch_all(selector \\ %{}, user \\ nil) do
    Contract.wallet_proposals()
    |> map_response()
    |> merge_db_proposals()
    |> filter_response(selector[:filter])
    |> filter_by_type(selector[:type], user)
    |> sort_response(selector[:sort_by])
    |> paginate(selector[:page], selector[:page_size])
  end

  defp votes_for_proposal(votes, proposal_id) do
    Enum.filter(votes, &(&1.proposal_id == proposal_id))
  end

  defp map_response(response) do
    votes = Contract.all_votes()

    response
    |> Enum.map(fn {
                     proposal_id,
                     hunter_address,
                     reward,
                     state,
                     is_reward_claimed,
                     created_at,
                     finish_at,
                     votes_for,
                     votes_against,
                     sheriffs_reward_share,
                     fixed_sheriff_reward
                   } ->
      votes_for_proposal = votes_for_proposal(votes, proposal_id)

      %{
        proposal_id: proposal_id,
        hunter_address: encode_address(hunter_address),
        reward: format_number(reward),
        state: @states_map[state],
        is_reward_claimed: is_reward_claimed,
        created_at: DateTime.from_unix!(created_at),
        finish_at: DateTime.from_unix!(finish_at),
        votes_for: format_number(votes_for),
        votes_against: format_number(votes_against),
        sheriffs_reward_share: sheriffs_reward_share,
        fixed_sheriff_reward: format_number(fixed_sheriff_reward),
        votes: votes_for_proposal,
        votes_count: length(votes_for_proposal)
      }
    end)
  end

  defp filter_response(response, nil), do: response

  defp filter_response(response, filter) do
    response
    |> Enum.filter(fn proposal ->
      Enum.map(filter, fn %{field: field, value: value} ->
        field = String.to_existing_atom(field)
        to_string(proposal[field]) == value
      end)
      |> Enum.all?()
    end)
  end

  defp filter_by_type(response, nil, _), do: response
  defp filter_by_type(response, :all, _), do: response
  defp filter_by_type(_, :only_voted, nil), do: []
  defp filter_by_type(_, :only_mine, nil), do: []

  defp filter_by_type(response, :only_voted, user) do
    user_wallets = EthAccount.wallets_by_user(user.id)

    response
    |> Enum.filter(fn proposal ->
      voted_addresses = Enum.map(proposal.votes, &String.downcase(&1.voter_address))

      intersection =
        MapSet.intersection(MapSet.new(voted_addresses), MapSet.new(user_wallets))
        |> Enum.to_list()

      intersection != []
    end)
  end

  defp filter_by_type(response, :only_mine, user) do
    proposal_ids = fetch_all_proposal_ids_by_user(user)

    response
    |> Enum.filter(fn proposal ->
      proposal.proposal_id in proposal_ids
    end)
  end

  defp sort_response(response, nil), do: response

  defp sort_response(response, %{field: field, direction: direction}) do
    field = String.to_existing_atom(field)

    direction = if field in [:created_at, :finish_at], do: {direction, DateTime}, else: direction
    Enum.sort_by(response, & &1[field], direction)
  end

  defp paginate(response, page, page_size) do
    page = page || 1
    page_size = page_size || 20
    start_index = (page - 1) * page_size
    Enum.slice(response, start_index, page_size)
  end

  defp merge_db_proposals(proposals) do
    proposal_ids = Enum.map(proposals, & &1.proposal_id)
    db_proposals = fetch_by_proposal_ids(proposal_ids)

    id_proposal_map =
      db_proposals
      |> Enum.into(%{}, fn %{proposal_id: proposal_id} = item -> {proposal_id, item} end)

    proposals = Enum.filter(proposals, &(id_proposal_map[&1[:proposal_id]] != nil))

    proposals
    |> Enum.map(fn proposal ->
      db_proposal = id_proposal_map[proposal[:proposal_id]] || %{}
      Map.merge(Map.from_struct(db_proposal), proposal)
    end)
  end

  defp fetch_by_proposal_ids(proposal_ids) do
    from(p in __MODULE__,
      where: p.proposal_id in ^proposal_ids,
      left_join: u in assoc(p, :user)
    )
    |> Repo.all()
    |> Repo.preload(:user)
  end

  defp fetch_all_proposal_ids_by_user(user) do
    from(p in __MODULE__, where: p.user_id == ^user.id, select: p.proposal_id)
    |> Repo.all()
  end

  defp maybe_add_user(%{user_id: _} = args), do: args

  defp maybe_add_user(args) do
    eth_account = EthAccount.by_address(args.hunter_address)

    if eth_account do
      Map.put(args, :user_id, eth_account.user_id)
    else
      args
    end
  end

  defp async_poll_transaction_status(transaction_id) do
    Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
      check_trx_events(transaction_id, 0)
    end)
  end

  defp check_trx_events(_, @retries_num), do: :ok

  defp check_trx_events(transaction_id, retries_so_far) do
    poll_transaction_and_maybe_update(transaction_id)
    |> case do
      {:ok, %__MODULE__{} = proposal} ->
        {:ok, proposal}

      _error ->
        Process.sleep(@sleep_time)
        check_trx_events(transaction_id, retries_so_far + 1)
    end
  end

  defp poll_transaction_and_maybe_update(transaction_id) do
    with {:ok, %{"blockNumber" => block_number}} when block_number != nil <-
           Contract.get_trx_by_id(transaction_id),
         {:ok, %{"logs" => logs} = receipt} when is_list(logs) <-
           Contract.get_trx_receipt_by_id(transaction_id) do
      if receipt["status"] == "0x1" and logs != [] do
        event = hd(logs)

        case event["topics"] do
          [_, proposal_id, _] when is_binary(proposal_id) ->
            proposal_id = proposal_id |> String.slice(2..-1) |> Integer.parse(16) |> elem(0)

            update_by_transaction_id(transaction_id, %{
              proposal_id: proposal_id,
              transaction_status: "ok"
            })

          _ ->
            update_by_transaction_id(transaction_id, %{transaction_status: "error"})
        end
      else
        update_by_transaction_id(transaction_id, %{transaction_status: "error"})
      end
    end
  end

  defp update_by_transaction_id(transaction_id, params) do
    fetch_by_transaction_id(transaction_id)
    |> changeset(params)
    |> Repo.update()
  end

  defp normalize_text(changeset, _field, nil), do: changeset

  defp normalize_text(changeset, field, value) do
    put_change(changeset, field, sanitize_markdown(value))
  end

  defp validate_address(field, address) do
    case Regex.match?(~r/^0x([A-Fa-f0-9]{40})$/, address) do
      true -> []
      false -> [{field, "Invalid Ethereum address!"}]
    end
  end

  defp preload({:ok, db_proposal}) do
    {:ok, Repo.preload(db_proposal, :user)}
  end

  defp preload(error), do: error
end
