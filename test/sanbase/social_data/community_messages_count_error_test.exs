defmodule Sanbase.SocialData.CommunityMessagesCountErrorTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.SocialData.Community

  @from ~U[2019-01-01 00:00:00Z]
  @to ~U[2019-01-03 00:00:00Z]

  @tag capture_log: true
  test "total source returns an error tuple when a source request fails" do
    Sanbase.Mock.prepare_mock2(
      &HTTPoison.get/3,
      {:ok, %HTTPoison.Response{status_code: 500, body: "Internal Server Error"}}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert {:error, _reason} = run(:total)
    end)
  end

  @tag capture_log: true
  test "total source returns an error tuple when only one source fails" do
    ok_body = ~s({"data": {"2019-01-01T00:00:00Z": 100, "2019-01-02T00:00:00Z": 200}})

    Sanbase.Mock.prepare_mock(HTTPoison, :get, fn _url, _headers, options ->
      source = options |> Keyword.fetch!(:params) |> List.keyfind("source", 0) |> elem(1)

      case source do
        "telegram" -> {:ok, %HTTPoison.Response{status_code: 200, body: ok_body}}
        "reddit" -> {:error, %HTTPoison.Error{reason: :timeout}}
      end
    end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert {:error, _reason} = run("total")
    end)
  end

  test "single source still returns the data on success" do
    ok_body = ~s({"data": {"2019-01-01T00:00:00Z": 100, "2019-01-02T00:00:00Z": 200}})

    Sanbase.Mock.prepare_mock2(
      &HTTPoison.get/3,
      {:ok, %HTTPoison.Response{status_code: 200, body: ok_body}}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert {:ok,
              [
                %{datetime: ~U[2019-01-01 00:00:00Z], mentions_count: 100},
                %{datetime: ~U[2019-01-02 00:00:00Z], mentions_count: 200}
              ]} = run(:telegram)
    end)
  end

  defp run(source) do
    Community.community_messages_count(%{slug: "santiment"}, @from, @to, "1d", source)
  end
end
