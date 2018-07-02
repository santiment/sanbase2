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
  alias Sanbase.Auth.UserApikeyToken
  alias Sanbase.Auth.User

  @rand_bytes_length 64
  @apikey_length 32

  def hmac(apikey) do
    :crypto.hmac(:sha256, secret_key(), apikey)
    |> Base.encode32(case: :lower)
    |> binary_part(0, @apikey_length)
  end

  def generate_token() do
    :crypto.strong_rand_bytes(@rand_bytes_length)
    |> Base.encode32(case: :lower)
    |> binary_part(0, @apikey_length)
  end

  def generate_apikey(token) do
    token <> "_" <> hmac(token)
  end

  def apikey_valid?(token, apikey) do
    UserApikeyToken.has_token?(token) and apikey == generate_apikey(token)
  end

  def split_apikey(token_apikey) do
    [token, apikey] = String.split(token_apikey, "_", parts: 2)
    {:ok, {token, apikey}}
  end

  # Private functions

  defp secret_key(), do: Config.get(:secret_key)
end
