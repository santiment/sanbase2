defmodule Sanbase.Accounts.EthLoginChallenge do
  @moduledoc ~s"""
  One-time messages for wallet login and for linking a wallet to an account.

  The old wallet login signs the fixed text "Login in Santiment with address X",
  so a signature for it never expires: anyone who sees one (in a log, a proxy, a
  browser extension) can log in as that wallet forever.

  With a challenge, the client first asks for a message (`create/1`). The
  message contains a random nonce and an expiry, the wallet signs that exact
  text, and `ethLogin` sends the nonce back. The server checks the signature
  against the stored message and marks the nonce as used (`consume/2`), so every
  signature works once and only for `@ttl_seconds`.

  While an address has an open challenge with enough time left to sign, `create/1`
  returns that same challenge instead of a new one. The nonce is not a secret (only
  the wallet can sign it), so handing it to another caller is harmless, and nobody
  can block a wallet's login by asking for challenges for its address.

  Rows are stored in Postgres, so a challenge created on one node can be used on
  any other. Rows are never deleted: they record which addresses asked to log in
  and when, and are kept as evidence. Handing out the open challenge again (see
  `create/1`) limits how often a new row is added for an address: at most one
  every `@ttl_seconds - @min_seconds_left_to_reuse` seconds. It does not limit
  how many rows an address has in total, which keeps growing over time.
  """

  use Ecto.Schema

  import Ecto.Query

  alias Sanbase.Repo

  @ttl_seconds 300
  # The first line of each kind of message. The purpose is part of the signed
  # text, so a signature for one operation cannot be replayed for another.
  @login_prefix "Login in Santiment with address "
  @link_prefix "Link address "
  # An open challenge is handed out again only if the wallet still has this long to sign it.
  @min_seconds_left_to_reuse 120

  schema "eth_login_challenges" do
    field(:address, :string)
    field(:nonce, :string)
    field(:message, :string)
    field(:expires_at, :utc_datetime)
    field(:used_at, :utc_datetime)

    timestamps()
  end

  def ttl_seconds(), do: @ttl_seconds

  @doc ~s"""
  Get a challenge for `address`. Returns the message the wallet must sign, the
  nonce to send back with `ethLogin`, and when it expires.

  Reuses the address's newest open challenge while it has at least
  `@min_seconds_left_to_reuse` seconds left, otherwise creates a new one.
  """
  @spec create(String.t()) ::
          {:ok, %{message: String.t(), nonce: String.t(), expires_at: DateTime.t()}}
          | {:error, String.t()}
  def create(address) when is_binary(address) do
    address = String.trim(address)

    with :ok <- validate_address(address) do
      case reusable_challenge(address, @login_prefix <> "%") do
        nil -> insert_challenge(address, &build_message(address, &1, &2, &3))
        challenge -> {:ok, challenge}
      end
    end
  end

  @doc ~s"""
  Get a challenge for linking `address` to the account of `user_id`
  (`addUserEthAddress`). Same rules as `create/1`, but the message names the
  operation and the account, so the signature can only link the wallet to that
  account, and a login signature can never be used to link a wallet (or the
  other way around).
  """
  @spec create_link(String.t(), non_neg_integer()) ::
          {:ok, %{message: String.t(), nonce: String.t(), expires_at: DateTime.t()}}
          | {:error, String.t()}
  def create_link(address, user_id) when is_binary(address) and is_integer(user_id) do
    address = String.trim(address)

    with :ok <- validate_address(address) do
      case reusable_challenge(address, "#{@link_prefix}% to Santiment account #{user_id}\n%") do
        nil -> insert_challenge(address, &build_link_message(address, user_id, &1, &2, &3))
        challenge -> {:ok, challenge}
      end
    end
  end

  @doc "Whether a stored challenge message is a login challenge."
  @spec login_message?(String.t()) :: boolean()
  def login_message?(message), do: String.starts_with?(message, @login_prefix)

  @doc "Whether a stored challenge message links a wallet to the account of `user_id`."
  @spec link_message_for?(String.t(), non_neg_integer()) :: boolean()
  def link_message_for?(message, user_id) do
    String.starts_with?(message, @link_prefix) and
      String.contains?(message, " to Santiment account #{user_id}\n")
  end

  defp insert_challenge(address, build_message_fun) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    expires_at = DateTime.add(now, @ttl_seconds, :second)
    nonce = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    message = build_message_fun.(nonce, now, expires_at)

    %__MODULE__{
      address: normalize(address),
      nonce: nonce,
      message: message,
      expires_at: expires_at
    }
    |> Repo.insert()
    |> case do
      {:ok, _} -> {:ok, %{message: message, nonce: nonce, expires_at: expires_at}}
      {:error, _} -> {:error, "Could not create a wallet login challenge"}
    end
  end

  @doc ~s"""
  Get the message of an open challenge (not used, not expired) for `address`.
  """
  @spec get_open(String.t(), String.t()) :: {:ok, String.t()} | {:error, :invalid_challenge}
  def get_open(address, nonce) when is_binary(address) and is_binary(nonce) do
    now = DateTime.utc_now()

    from(c in __MODULE__,
      where:
        c.nonce == ^nonce and c.address == ^normalize(address) and is_nil(c.used_at) and
          c.expires_at > ^now,
      select: c.message
    )
    |> Repo.one()
    |> case do
      nil -> {:error, :invalid_challenge}
      message -> {:ok, message}
    end
  end

  @doc ~s"""
  Mark the challenge as used. Atomic: when two requests race with the same
  nonce, only one of them gets `:ok`.
  """
  @spec consume(String.t(), String.t()) :: :ok | {:error, :invalid_challenge}
  def consume(address, nonce) when is_binary(address) and is_binary(nonce) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(c in __MODULE__,
      where:
        c.nonce == ^nonce and c.address == ^normalize(address) and is_nil(c.used_at) and
          c.expires_at > ^now
    )
    |> Repo.update_all(set: [used_at: now, updated_at: DateTime.to_naive(now)])
    |> case do
      {1, _} -> :ok
      _ -> {:error, :invalid_challenge}
    end
  end

  @doc false
  def build_message(address, nonce, issued_at, expires_at) do
    """
    #{@login_prefix}#{address}
    Nonce: #{nonce}
    Issued at: #{DateTime.to_iso8601(issued_at)}
    Expires at: #{DateTime.to_iso8601(expires_at)}\
    """
  end

  @doc false
  def build_link_message(address, user_id, nonce, issued_at, expires_at) do
    """
    #{@link_prefix}#{address} to Santiment account #{user_id}
    Nonce: #{nonce}
    Issued at: #{DateTime.to_iso8601(issued_at)}
    Expires at: #{DateTime.to_iso8601(expires_at)}\
    """
  end

  defp normalize(address), do: String.downcase(address)

  defp validate_address(address) do
    if Regex.match?(~r/\A0x[0-9a-fA-F]{40}\z/, address),
      do: :ok,
      else: {:error, "Invalid wallet address"}
  end

  # Handing out the open challenge again means asking for challenges in a loop adds
  # a new row only once the open one is close to expiring, and never locks the owner
  # out. The total number of rows per address is not limited.
  # Only a challenge of the same kind (and, for linking, the same account) is
  # reused, matched by the message's first line.
  defp reusable_challenge(address, message_pattern) do
    reuse_until = DateTime.utc_now() |> DateTime.add(@min_seconds_left_to_reuse, :second)

    from(c in __MODULE__,
      where:
        c.address == ^normalize(address) and is_nil(c.used_at) and
          c.expires_at > ^reuse_until and like(c.message, ^message_pattern),
      order_by: [desc: c.expires_at],
      limit: 1,
      select: %{message: c.message, nonce: c.nonce, expires_at: c.expires_at}
    )
    |> Repo.one()
  end
end
