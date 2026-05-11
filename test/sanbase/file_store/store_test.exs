defmodule Sanbase.FileStoreTest do
  use ExUnit.Case, async: true

  alias Sanbase.FileStore

  test "skips storing non-image variant versions" do
    assert FileStore.transform(:w400, {%{file_name: "report.pdf"}, "scope"}) == :skip
    assert FileStore.transform(:w800, {%{file_name: "data.csv"}, "scope"}) == :skip
    assert FileStore.transform(:w1200, {%{file_name: "clip.mp4"}, "scope"}) == :skip
    assert FileStore.transform(:w2000, {%{file_name: "report.PDF"}, "scope"}) == :skip
  end
end
