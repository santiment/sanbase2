defmodule Sanbase.SocialData.CommunityMessagesCountErrorTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.SocialData.Community

  @from ~U[2019-01-01 00:00:00Z]
  @to ~U[2019-01-03 00:00:00Z]
  @ok_body ~s({"data": {"2019-01-01T00:00:00Z": 100, "2019-01-02T00:00:00Z": 200}})

  @moduletag capture_log: true

  test "single source returns an error when the response is not JSON" do
    Sanbase.Mock.prepare_mock2(
      &HTTPoison.get/3,
      {:ok, %HTTPoison.Response{status_code: 200, body: "<html>not json</html>"}}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert {:error, _} = run(:telegram)
    end)
  end

  test "total source returns an error when one source fails" do
    Sanbase.Mock.prepare_mock(HTTPoison, :get, fn _url, _headers, options ->
      case options |> Keyword.fetch!(:params) |> List.keyfind("source", 0) do
        {"source", "telegram"} -> {:ok, %HTTPoison.Response{status_code: 200, body: @ok_body}}
        {"source", "reddit"} -> {:error, %HTTPoison.Error{reason: :timeout}}
      end
    end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert {:error, _} = run("total")
    end)
  end

  test "total source returns an error when a source request crashes" do
    Process.flag(:trap_exit, true)

    Sanbase.Mock.prepare_mock(HTTPoison, :get, fn _url, _headers, _options -> exit(:boom) end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert {:error, _} = run(:total)
    end)
  end

  defp run(source) do
    Community.community_messages_count(%{slug: "santiment"}, @from, @to, "1d", source)
  end
end
