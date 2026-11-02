defmodule Sanbase.Accounts.EthLoginChallengeTest do
  use Sanbase.DataCase, async: true

  alias Sanbase.Accounts.EthLoginChallenge

  @address "0x9024d48cc7be15343dfd76ef051fa5264cfbf7a9"

  describe "create/1" do
    test "returns a message with the address, a nonce and an expiry" do
      assert {:ok, %{message: message, nonce: nonce, expires_at: expires_at}} =
               EthLoginChallenge.create(@address)

      assert message =~ "Login in Santiment with address #{@address}"
      assert message =~ "Nonce: #{nonce}"
      assert String.length(nonce) == 32
      assert DateTime.diff(expires_at, DateTime.utc_now()) in 290..300
    end

    test "every challenge has a different nonce" do
      {:ok, %{nonce: nonce1}} = EthLoginChallenge.create(@address)
      {:ok, %{nonce: nonce2}} = EthLoginChallenge.create(@address)

      assert nonce1 != nonce2
    end

    test "rejects something that is not a wallet address" do
      assert {:error, "Invalid wallet address"} = EthLoginChallenge.create("not-an-address")
      assert {:error, "Invalid wallet address"} = EthLoginChallenge.create("0x1234")
    end

    test "caps the number of open challenges per address" do
      for _ <- 1..10, do: {:ok, _} = EthLoginChallenge.create(@address)

      assert {:error, "Too many wallet login attempts" <> _} = EthLoginChallenge.create(@address)

      # Other addresses are not affected.
      assert {:ok, _} = EthLoginChallenge.create("0x" <> String.duplicate("a", 40))
    end

    test "removes expired challenges" do
      {:ok, %{nonce: nonce}} = EthLoginChallenge.create(@address)
      expire!(nonce)

      {:ok, _} = EthLoginChallenge.create(@address)

      refute Sanbase.Repo.get_by(EthLoginChallenge, nonce: nonce)
    end
  end

  describe "get_open/2 and consume/2" do
    test "a challenge can be used once" do
      {:ok, %{nonce: nonce, message: message}} = EthLoginChallenge.create(@address)

      assert {:ok, ^message} = EthLoginChallenge.get_open(@address, nonce)
      assert :ok = EthLoginChallenge.consume(@address, nonce)

      assert {:error, :invalid_challenge} = EthLoginChallenge.get_open(@address, nonce)
      assert {:error, :invalid_challenge} = EthLoginChallenge.consume(@address, nonce)
    end

    test "the address is compared case-insensitively" do
      {:ok, %{nonce: nonce}} = EthLoginChallenge.create(@address)

      assert :ok = EthLoginChallenge.consume(String.upcase(@address), nonce)
    end

    test "a challenge belongs to its address" do
      {:ok, %{nonce: nonce}} = EthLoginChallenge.create(@address)
      other = "0x" <> String.duplicate("b", 40)

      assert {:error, :invalid_challenge} = EthLoginChallenge.get_open(other, nonce)
      assert {:error, :invalid_challenge} = EthLoginChallenge.consume(other, nonce)
      assert :ok = EthLoginChallenge.consume(@address, nonce)
    end

    test "an expired challenge cannot be used" do
      {:ok, %{nonce: nonce}} = EthLoginChallenge.create(@address)
      expire!(nonce)

      assert {:error, :invalid_challenge} = EthLoginChallenge.get_open(@address, nonce)
      assert {:error, :invalid_challenge} = EthLoginChallenge.consume(@address, nonce)
    end

    test "an unknown nonce is rejected" do
      assert {:error, :invalid_challenge} = EthLoginChallenge.consume(@address, "nope")
    end
  end

  defp expire!(nonce) do
    past = DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.truncate(:second)

    Sanbase.Repo.get_by!(EthLoginChallenge, nonce: nonce)
    |> Ecto.Changeset.change(expires_at: past)
    |> Sanbase.Repo.update!()
  end
end
