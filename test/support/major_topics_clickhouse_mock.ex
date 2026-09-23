defmodule Sanbase.MajorTopicsClickhouseMock do
  @moduledoc """
  Mocks the ClickHouse queries of `Sanbase.MajorTopics.ClickhouseFetcher`.

  `versions` maps interval => highest version stored in ClickHouse. The
  metadata rows are generated for whichever version is asked for, with titles
  `"v<version> topic <idx>"`. The mock is global, so tests using it cannot run
  async.
  """

  def with_clickhouse(versions, fun) do
    query = fn sql, args, _opts ->
      rows =
        cond do
          sql =~ "max(interval)" ->
            [[versions |> Map.keys() |> Enum.max()]]

          sql =~ "max(version)" ->
            Enum.map(versions, fn {interval, version} -> [interval, version] end)

          sql =~ "FROM major_topics_metadata" ->
            %{"version" => version, "interval" => interval} = args

            Enum.map(0..1, fn idx ->
              [
                "#{version};#{idx};twitter_crypto;#{interval};bertopic",
                idx,
                "v#{version} topic #{idx}",
                "Summary #{idx}.",
                true,
                "bertopic",
                [~s({"word": "word#{idx}", "score": 1.0})]
              ]
            end)

          sql =~ "FROM major_topics_values" ->
            %{"ids" => ids} = args
            Enum.map(ids, fn id -> [id, 1, 1_789_084_800] end)
        end

      {:ok, %{rows: rows}}
    end

    Sanbase.Mock.prepare_mock(Sanbase.ClickhouseRepo, :query, query)
    |> Sanbase.Mock.run_with_mocks(fun)
  end
end
