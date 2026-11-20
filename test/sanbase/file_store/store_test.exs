defmodule Sanbase.FileStoreTest do
  use ExUnit.Case, async: true

  alias Sanbase.FileStore

  test "skips storing non-image variant versions" do
    assert FileStore.transform(:w400, {%{file_name: "report.pdf"}, "scope"}) == :skip
    assert FileStore.transform(:w800, {%{file_name: "data.csv"}, "scope"}) == :skip
    assert FileStore.transform(:w1200, {%{file_name: "clip.mp4"}, "scope"}) == :skip
    assert FileStore.transform(:w2000, {%{file_name: "report.PDF"}, "scope"}) == :skip
  end

  describe "download_filename/1" do
    test "strips the version, content hash and timestamp prefixes" do
      hash = String.duplicate("a1b2", 16)

      assert FileStore.download_filename(
               "uploads/#{hash}_1788517501277_Santiment_August_2026_Report.pdf"
             ) == "Santiment_August_2026_Report.pdf"

      assert FileStore.download_filename("w400_#{hash}_1788517501277_image.png") == "image.png"
    end

    test "keeps a name that has no generated prefixes" do
      assert FileStore.download_filename("Santiment_August_2026_Report.pdf") ==
               "Santiment_August_2026_Report.pdf"
    end

    test "keeps digits that are part of the original name" do
      hash = String.duplicate("a1b2", 16)

      assert FileStore.download_filename("#{hash}_1788517501277_2026_report.pdf") ==
               "2026_report.pdf"
    end
  end

  describe "content_disposition/1" do
    test "is set for downloadable files" do
      hash = String.duplicate("a1b2", 16)

      assert FileStore.content_disposition("#{hash}_1788517501277_Santiment_Report.pdf") ==
               ~s|attachment; filename="Santiment_Report.pdf"; filename*=UTF-8''Santiment_Report.pdf|

      assert FileStore.content_disposition("#{hash}_1788517501277_data.CSV") ==
               ~s|attachment; filename="data.CSV"; filename*=UTF-8''data.CSV|
    end

    test "is not set for files that are rendered inline" do
      assert FileStore.content_disposition("hash_123_image.png") == nil
      assert FileStore.content_disposition("hash_123_clip.mp4") == nil
    end

    test "escapes the ascii fallback and percent encodes the utf8 name" do
      assert FileStore.content_disposition(~s|repo"rt отчет.pdf|) ==
               ~s|attachment; filename="repo_rt _____.pdf"; | <>
                 "filename*=UTF-8''repo%22rt%20%D0%BE%D1%82%D1%87%D0%B5%D1%82.pdf"
    end
  end

  describe "s3_object_headers/2" do
    test "adds a content disposition only for downloadable files" do
      hash = String.duplicate("a1b2", 16)
      stored_name = "#{hash}_1788517501277_report.pdf"

      headers = FileStore.s3_object_headers(:original, {%{file_name: stored_name}, hash})

      assert Keyword.fetch!(headers, :content_disposition) =~ ~s|filename="report.pdf"|
      assert Keyword.has_key?(headers, :cache_control)

      headers =
        FileStore.s3_object_headers(:original, {%{file_name: "#{hash}_1_image.png"}, hash})

      refute Keyword.has_key?(headers, :content_disposition)
      assert Keyword.has_key?(headers, :cache_control)
    end
  end
end
