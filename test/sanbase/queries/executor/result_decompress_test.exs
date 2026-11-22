defmodule Sanbase.Queries.Executor.ResultDecompressTest do
  @moduledoc """
  SECURITY_ANALYSIS.md B2: `decode_and_decompress/2` takes client input
  (`storeQueryExecution` / `storeDashboardQueryExecution`), so it must not
  inflate a decompression bomb into memory.
  """
  use ExUnit.Case, async: true

  alias Sanbase.Queries.Executor.Result

  defp encode(data), do: data |> :zlib.gzip() |> Base.encode64()

  test "round-trips a normal compressed value" do
    json = Jason.encode!(%{columns: ["a"], rows: [[1], [2]]})

    assert Result.decode_and_decompress(encode(json)) == {:ok, json}
  end

  test "rejects a value that decompresses over the limit" do
    # 10KB of zeros compresses to a few dozen bytes.
    bomb = encode(:binary.copy(<<0>>, 10_000))

    assert {:error, error} = Result.decode_and_decompress(bomb, max_decompressed_bytes: 1_000)
    assert error =~ "decompressed value is over the limit"

    assert {:ok, _} = Result.decode_and_decompress(bomb, max_decompressed_bytes: 10_000)
  end

  test "the default limit stops a real bomb without inflating it fully" do
    # 60MB of zeros compresses to ~60KB: over the 50MB default.
    bomb = encode(:binary.copy(<<0>>, 60 * 1024 * 1024))
    assert byte_size(bomb) < 200_000

    assert {:error, error} = Result.decode_and_decompress(bomb)
    assert error =~ "decompressed value is over the limit of 50MB"
  end

  test "rejects an encoded value over the input limit before decoding it" do
    assert {:error, error} =
             Result.decode_and_decompress(encode("small"), max_encoded_bytes: 5)

    assert error =~ "over the limit"
  end

  test "keeps the existing error messages for invalid input" do
    assert Result.decode_and_decompress("not base64 !!") ==
             {:error, "The provided value is not a valid base64-encoded binary"}

    assert Result.decode_and_decompress(Base.encode64("hehe")) ==
             {:error, "The provided value is not a valid gzip binary"}
  end

  test "a truncated gzip stream is rejected rather than looping" do
    # Random bytes do not compress, so cutting the stream leaves real data missing.
    gzip = :zlib.gzip(:crypto.strong_rand_bytes(100_000))
    truncated = binary_part(gzip, 0, div(byte_size(gzip), 2)) |> Base.encode64()

    assert Result.decode_and_decompress(truncated) ==
             {:error, "The provided value is not a valid gzip binary"}
  end

  test "decodes every member of a concatenated gzip, like :zlib.gunzip/1" do
    encoded = (:zlib.gzip("{\"rows\":") <> :zlib.gzip("[[1]]}")) |> Base.encode64()

    assert Result.decode_and_decompress(encoded) == {:ok, "{\"rows\":[[1]]}"}
  end

  test "the output limit spans all members of a concatenated gzip" do
    member = :zlib.gzip(:binary.copy(<<0>>, 600))
    encoded = (member <> member) |> Base.encode64()

    assert {:error, error} = Result.decode_and_decompress(encoded, max_decompressed_bytes: 1_000)
    assert error =~ "decompressed value is over the limit"
  end

  test "accepts a valid gzip whose header is consumed without producing output" do
    # A 9000-byte FNAME header: the first inflate calls consume input but output nothing.
    data = "small"
    z = :zlib.open()
    :ok = :zlib.deflateInit(z, :default, :deflated, -15, 8, :default)
    raw_deflate = z |> :zlib.deflate(data, :finish) |> IO.iodata_to_binary()
    :zlib.close(z)

    gzip =
      <<0x1F, 0x8B, 8, 0x08, 0::32, 0, 3>> <>
        :binary.copy("a", 9000) <>
        <<0>> <>
        raw_deflate <>
        <<:erlang.crc32(data)::little-32, byte_size(data)::little-32>>

    assert :zlib.gunzip(gzip) == data
    assert Result.decode_and_decompress(Base.encode64(gzip)) == {:ok, data}
  end
end
