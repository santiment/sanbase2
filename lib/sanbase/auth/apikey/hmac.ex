defmodule Sanbase.Auth.Hmac do
  @moduledoc """
  What is HMAC? HMAC is a way to combine a key and a hashing function in a way
  that's harder to attack. HMAC does not encrypt the message.

  The calculation is the following:
  `HMAC(K,m) = H((K' ⊕ opad) || H ((K' ⊕ ipad)||m))`
  where
    - H is a cryptographic hash function,
    - K is the secret key,
    - m is the message to be authenticated,
    - K' is another secret key, derived from the original key K
    (by padding K to the right with extra zeroes to the input block size of the hash function,
    or by hashing K if it is longer than that block size),
    - || denotes concatenation,
    - ⊕ denotes exclusive or (XOR),
    - opad is the outer padding (0x5c5c5c…5c5c, one-block-long hexadecimal constant),
    - ipad is the inner padding (0x363636…3636, one-block-long hexadecimal constant).

    ipad and opad are choosed to have large Hamming distance

  Currently the apikey does not give access to mutations but only gives access to read
  data that requires authentication and possibly SAN staking.

  We use HMAC to solve a particular problem - we should be able to show the users
  the apikey in plain text at any time but we also should not store the apikey in plaintext
  in the database. Because of this the following approach has been choosen:
    1. Have a secret key on the server
    2. When a apikey generation request is made, generate a token and store it in the database
    3. Feed the HMAC algorithm the sha256 hashing function, the secret key and generated token.
    The result of the HMAC is the apikey.
    4. For easier search in the database prepend the apikey with the user id
  """
  import Ecto.Query

  require Sanbase.Utils.Config
  require Logger

  alias Sanbase.Utils.Config
  alias Sanbase.Auth.UserApiKeyToken
  alias Sanbase.Auth.User

  @rand_bytes_length 64
  @api_key_length 32

  def hmac(api_key) do
    api_key_secret =
      :crypto.hmac(:sha256, secret_key(), api_key)
      |> Base.encode16()
      |> binary_part(0, @api_key_length)
  end

  def generate_token() do
    :crypto.strong_rand_bytes(@rand_bytes_length)
    |> Base.encode16()
    |> binary_part(0, @api_key_length)
  end

  def generate_api_key_secret(id, token) do
    api_key_secret = "#{id}_" <> token
  end

  def api_key_secret_to_user(id_api_key_secret) do
    with [num_as_str, api_key_secret] <- String.split(id_api_key_secret, "_", parts: 2),
         {user_id, _rest} <- Integer.parse(num_as_str) do
      query =
        from(
          pair in UserApiKeyToken,
          where: pair.user_id == ^user_id,
          select: pair.token
        )

      tokens = Sanbase.Repo.all(query)

      if api_key_secret_valid?(user_id, tokens, api_key_secret) do
        fetch_user(user_id)
      else
        {:error, "Apikey not valid"}
      end
    else
      error ->
        {:error, "Provided apikey is malformed"}
    end
  end

  defp secret_key(), do: Config.get(:secret_key)

  defp api_key_secret_valid?(user_id, tokens, api_key_secret) do
    Enum.find(tokens, fn token ->
      generate_api_key_secret(user_id, token) == api_key_secret
    end)
    |> case do
      nil -> false
      _ -> true
    end
  end

  defp fetch_user(user_id) do
    case Repo.one(User, user_id) do
      nil ->
        {:error, "Cannot fetch the user with id #{user_id}"}

      user ->
        {:ok, user}
    end
  end
end
