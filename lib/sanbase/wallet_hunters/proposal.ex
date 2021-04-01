defmodule Sanbase.WalletHunters.Proposal do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query
  import Sanbase.SmartContracts.Utils

  alias Sanbase.Repo
  alias Sanbase.Accounts.{User, EthAccount}
  alias Sanbase.WalletHunters.Contract

  @states_map %{
    0 => :active,
    1 => :approved,
    2 => :declined,
    3 => :discarded
  }

  schema "wallet_hunters_proposals" do
    field(:hunter_address, :string)
    field(:proposal_id, :integer)
    field(:text, :string)
    field(:title, :string)

    field(:proposed_address, :string)
    field(:user_labels, {:array, :string}, default: [])

    belongs_to(:user, User)

    timestamps()
  end

  @doc false
  def changeset(proposal, attrs) do
    proposal
    |> cast(attrs, [
      :title,
      :text,
      :proposal_id,
      :hunter_address,
      :user_id,
      :proposed_address,
      :user_labels
    ])
    |> normalize_text(:text, attrs[:text])
    |> validate_required([:title, :text, :proposal_id, :hunter_address, :proposed_address])
    |> unique_constraint(:proposal_id)
  end

  def sanitize_markdown(markdown) do
    # mark lines that start with "> " (valid markdown blockquote syntax)
    markdown = Regex.replace(~r/^>\s+([^\s+])/m, markdown, "REPLACED_BLOCKQUOTE\\1")
    markdown = HtmlSanitizeEx.markdown_html(markdown)
    # Bring back the blockquotes
    Regex.replace(~r/^REPLACED_BLOCKQUOTE/m, markdown, "> ")
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

  def fetch_by_id(proposal_id) do
    with proposal <- Contract.wallet_proposal(proposal_id) do
      proposal =
        proposal
        |> List.wrap()
        |> map_response()
        |> merge_db_proposals()
        |> hd()

      {:ok, proposal}
    end
  end

  def fetch_all(selector \\ %{}, user \\ nil) do
    proposals =
      Contract.wallet_proposals()
      |> map_response()
      |> filter_response(selector[:filter])
      |> filter_by_type(selector[:type], user)
      |> sort_response(selector[:sort_by])
      |> paginate(selector[:page], selector[:page_size])
      |> merge_db_proposals()

    {:ok, proposals}
  end

  defp votes_for_proposal(votes, proposal_id) do
    Enum.filter(votes, &(&1.proposal_id == proposal_id))
  end

  defp map_response(response) do
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
      votes_for_proposal =
        Contract.all_votes()
        |> votes_for_proposal(proposal_id)

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
    page_size = page_size || 10
    start_index = (page - 1) * page_size
    Enum.slice(response, start_index, page_size)
  end

  defp merge_db_proposals(proposals) do
    proposal_ids = Enum.map(proposals, & &1.proposal_id)
    db_proposals = fetch_by_proposal_ids(proposal_ids)

    id_proposal_map =
      db_proposals
      |> Enum.into(%{}, fn %{proposal_id: proposal_id} = item -> {proposal_id, item} end)

    proposals
    |> Enum.map(fn proposal ->
      db_proposal = id_proposal_map[proposal[:proposal_id]] || %{}
      Map.merge(proposal, db_proposal)
    end)
  end

  defp fetch_by_proposal_ids(proposal_ids) do
    from(p in __MODULE__,
      where: p.proposal_id in ^proposal_ids,
      join: u in assoc(p, :user),
      select: %{
        proposal_id: p.proposal_id,
        title: p.title,
        text: p.text,
        user: u,
        user_labels: p.user_labels,
        proposed_address: p.proposed_address
      }
    )
    |> Repo.all()
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

  defp normalize_text(changeset, field, value) do
    put_change(changeset, field, sanitize_markdown(value))
  end
end
