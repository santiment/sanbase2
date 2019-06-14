defmodule Sanbase.Auth.Hmac do
  @moduledoc """
  What is HMAC? HMAC is a way to combine a key and a hashing function in a way
  that's harder to attack.

  HMAC does not encrypt the message.

  The HMAC calculation is the following:
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
    4. For easier search in the database prepend the apikey with the token itself. This does not
    compromise the security as the real secret is the secret key and not the user token.
  """

  require Sanbase.Utils.Config, as: Config
  require Logger

  @rand_bytes_length 32
  @apikey_length 16

  @spec hmac(String.t()) :: String.t()
  def hmac(token) when is_binary(token) do
    :crypto.hmac(:sha256, secret_key(), token)
    |> Base.encode32(case: :lower)
    |> binary_part(0, byte_size(token))
  end

  @spec generate_token :: String.t()
  def generate_token() do
    :crypto.strong_rand_bytes(@rand_bytes_length)
    |> Base.encode32(case: :lower)
    |> binary_part(0, @apikey_length)
  end

  @spec generate_apikey(String.t()) :: String.t()
  def generate_apikey(token) do
    token <> "_" <> hmac(token)
  end

  @spec apikey_valid?(String.t(), String.t()) :: boolean
  def apikey_valid?(token, apikey) when byte_size(apikey) >= 32 and byte_size(token) >= 16 do
    apikey == generate_apikey(token)
  end

  def apikey_valid?(_, _), do: false

  @spec split_apikey(String.t()) :: {:ok, {String.t(), String.t()}} | {:error, String.t()}
  def split_apikey(token_apikey) do
    with [token, apikey] <- String.split(token_apikey, "_") do
      {:ok, {token, apikey}}
    else
      _error ->
        {:error,
         "Apikey '#{token_apikey}' is malformed - it must have two string parts separated by underscore"}
    end
  end

  # Private functions

  defp secret_key(), do: Config.get(:secret_key)
end
