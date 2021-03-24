defmodule Sanbase.WalletHunters.Proposal do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  import Sanbase.SmartContracts.Utils,
    only: [call_contract: 4, encode_address: 1, format_number: 1]

  alias Sanbase.Repo

  @contract "0x772e255402EEE3Fa243CB17AF58001f40Da78d90"
  @abi Path.join(__DIR__, "abis/wallet_hunters_abi.json")
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

    timestamps()
  end

  @doc false
  def changeset(proposal, attrs) do
    proposal
    |> cast(attrs, [:title, :text, :proposal_id, :hunter_address])
    |> validate_required([:title, :text, :proposal_id, :hunter_address])
    |> unique_constraint(:proposal_id)
  end

  def fetch_by_proposal_ids(proposal_ids) do
    from(p in __MODULE__,
      where: p.proposal_id in ^proposal_ids,
      select: %{proposal_id: p.proposal_id, title: p.title, text: p.text}
    )
    |> Repo.all()
  end

  def abi do
    File.read!(@abi)
    |> Jason.decode!()
    |> Map.get("abi")
  end

  def function_abi(function) do
    abi()
    |> ABI.parse_specification()
    |> Enum.filter(&(&1.function == function))
    |> hd()
  end

  def wallet_proposals_count() do
    call_contract(
      @contract,
      function_abi("walletProposalsLength"),
      [],
      function_abi("walletProposalsLength").returns
    )
    |> hd()
  end

  def wallet_proposals(limit \\ nil, offset \\ 0) do
    args = [offset, limit || wallet_proposals_count()]

    call_contract(
      @contract,
      function_abi("walletProposals"),
      args,
      function_abi("walletProposals").returns
    )
    |> hd()
  end

  def fetch_all(selector \\ %{}) do
    wallet_proposals()
    |> map_response()
    |> filter_response(selector[:filter])
    |> sort_response(selector[:sort_by])
    |> paginate(selector[:page], selector[:page_size])
    |> merge_db_proposals()
  end

  def map_response(response) do
    response
    |> Enum.map(fn {
                     proposal_id,
                     hunter_address,
                     reward,
                     state,
                     claimed_reward,
                     created_at,
                     finish_at,
                     votes_for,
                     votes_against,
                     sheriffs_reward_share,
                     fixed_sheriff_reward
                   } ->
      %{
        proposal_id: proposal_id,
        hunter_address: encode_address(hunter_address),
        reward: format_number(reward),
        state: @states_map[state],
        claimed_reward: claimed_reward,
        created_at: DateTime.from_unix!(created_at),
        finish_at: DateTime.from_unix!(finish_at),
        votes_for: format_number(votes_for),
        votes_against: format_number(votes_against),
        sheriffs_reward_share: sheriffs_reward_share,
        fixed_sheriff_reward: format_number(fixed_sheriff_reward)
      }
    end)
  end

  def filter_response(response, nil), do: response

  def filter_response(response, filter) do
    response
    |> Enum.filter(fn proposal ->
      Enum.map(filter, fn map ->
        field = String.to_existing_atom(map[:field])
        value = String.to_existing_atom(map[:value])
        proposal[field] == value
      end)
      |> Enum.all?()
    end)
  end

  def sort_response(response, nil), do: response

  def sort_response(response, %{field: field, direction: direction}) do
    field = String.to_existing_atom(field)

    if field in [:created_at, :finish_at] do
      Enum.sort_by(response, & &1[field], {direction, DateTime})
    else
      Enum.sort_by(response, & &1[field], direction)
    end
  end

  def paginate(response, page, page_size) do
    page = page || 1
    page_size = page_size || 10
    start_index = (page - 1) * page_size
    Enum.slice(response, start_index, page_size)
  end

  def merge_db_proposals(proposals) do
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
end
