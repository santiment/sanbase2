defmodule FixReportDownloadNamesTest do
  use ExUnit.Case, async: true

  # The script is not part of the compiled app, so it has to be loaded. Its
  # `mix run` entrypoint is skipped under MIX_ENV=test, nothing is executed.
  Code.require_file("../../scripts/fix_report_download_names.exs", __DIR__)

  alias FixReportDownloadNames, as: Fix

  @hash String.duplicate("a1b2", 16)
  @fallback "POSTS_IMAGE_BUCKET"

  # One url per shape a stored report can have.
  @urls [
    "https://mybucket.s3.amazonaws.com/uploads/#{@hash}_1611047725444_Report.pdf",
    "https://mybucket.s3.eu-central-1.amazonaws.com/uploads/Report.pdf",
    "https://s3.amazonaws.com/mybucket/uploads/Report.pdf",
    "https://s3.eu-central-1.amazonaws.com/mybucket/uploads/Report.pdf",
    "https://s3-eu-west-1.amazonaws.com/mybucket/uploads/Report.pdf",
    "https://cdn.example.net/uploads/Report.pdf",
    "https://cdn.example.net/Report.pdf",
    "https://mybucket.s3.amazonaws.com/uploads/My%20Report.pdf"
  ]

  describe "bucket_and_key/2" do
    test "reads the bucket off a virtual host url" do
      assert Fix.bucket_and_key(
               "https://mybucket.s3.amazonaws.com/uploads/#{@hash}_1611047725444_Report.pdf",
               @fallback
             ) == {"mybucket", "uploads/#{@hash}_1611047725444_Report.pdf"}

      assert Fix.bucket_and_key(
               "https://mybucket.s3.eu-central-1.amazonaws.com/uploads/Report.pdf",
               @fallback
             ) == {"mybucket", "uploads/Report.pdf"}
    end

    test "reads the bucket off the path of a path style url" do
      for host <- [
            "s3.amazonaws.com",
            "s3.eu-central-1.amazonaws.com",
            "s3-eu-west-1.amazonaws.com"
          ] do
        assert Fix.bucket_and_key("https://#{host}/mybucket/uploads/Report.pdf", @fallback) ==
                 {"mybucket", "uploads/Report.pdf"}
      end
    end

    test "keeps the whole path as the key when the host names no bucket" do
      # A CDN or a waffle `asset_host` url. Taking `uploads` for the bucket here
      # would send every later HEAD to a bucket that does not exist.
      assert Fix.bucket_and_key("https://cdn.example.net/uploads/Report.pdf", @fallback) ==
               {@fallback, "uploads/Report.pdf"}

      assert Fix.bucket_and_key("https://cdn.example.net/Report.pdf", @fallback) ==
               {@fallback, "Report.pdf"}
    end

    test "falls back when a path style url has no key after the bucket" do
      assert Fix.bucket_and_key("https://s3.amazonaws.com/Report.pdf", @fallback) ==
               {@fallback, "Report.pdf"}
    end

    test "decodes the key" do
      assert Fix.bucket_and_key(
               "https://mybucket.s3.amazonaws.com/uploads/My%20Report.pdf",
               @fallback
             ) ==
               {"mybucket", "uploads/My Report.pdf"}
    end
  end

  describe "build_url/2" do
    test "keeps the bucket segment of a path style url" do
      assert Fix.build_url(
               "https://s3.amazonaws.com/mybucket/uploads/#{@hash}_1611047725444_Report.pdf",
               "uploads/Report.pdf"
             ) == "https://s3.amazonaws.com/mybucket/uploads/Report.pdf"
    end

    test "replaces the path of a virtual host url" do
      assert Fix.build_url(
               "https://mybucket.s3.eu-central-1.amazonaws.com/uploads/#{@hash}_1611047725444_Report.pdf",
               "uploads/Report.pdf"
             ) == "https://mybucket.s3.eu-central-1.amazonaws.com/uploads/Report.pdf"
    end

    test "invents no bucket segment for a host that names none" do
      assert Fix.build_url("https://cdn.example.net/uploads/old.pdf", "uploads/Report.pdf") ==
               "https://cdn.example.net/uploads/Report.pdf"
    end

    test "encodes the new key" do
      assert Fix.build_url(
               "https://mybucket.s3.amazonaws.com/uploads/old.pdf",
               "uploads/My Report.pdf"
             ) ==
               "https://mybucket.s3.amazonaws.com/uploads/My%20Report.pdf"
    end

    test "is the inverse of bucket_and_key/2 for every url shape" do
      for url <- @urls do
        {_bucket, key} = Fix.bucket_and_key(url, @fallback)
        assert Fix.build_url(url, key) == url
      end
    end
  end

  describe "clean_key/1" do
    test "strips the generated prefixes and keeps the directory" do
      assert Fix.clean_key("uploads/#{@hash}_1611047725444_Santiment_Report.pdf") ==
               "uploads/Santiment_Report.pdf"
    end

    test "is idempotent, which is what marks a report as already clean" do
      clean = Fix.clean_key("uploads/#{@hash}_1611047725444_Santiment_Report.pdf")

      assert Fix.clean_key(clean) == clean
    end
  end

  describe "dated_key/1" do
    test "appends the upload date before the extension" do
      entry = %{
        old_key: "uploads/#{@hash}_1611047725444_Santiment Weekly Pro Report.pdf",
        base: "uploads/Santiment Weekly Pro Report.pdf"
      }

      assert Fix.dated_key(entry) == "uploads/Santiment Weekly Pro Report 2021-01-19.pdf"
    end

    test "is nil when the key carries no timestamp, so the group is skipped" do
      entry = %{old_key: "uploads/Report.pdf", base: "uploads/Report.pdf"}

      assert Fix.dated_key(entry) == nil
    end
  end

  describe "hash_from_key/1" do
    test "reads the content hash off the file name" do
      assert Fix.hash_from_key("uploads/#{String.upcase(@hash)}_1611047725444_Report.pdf") ==
               @hash
    end

    test "is nil when the name does not start with a hash" do
      assert Fix.hash_from_key("uploads/Report.pdf") == nil
      assert Fix.hash_from_key("uploads/1611047725444_Report.pdf") == nil
    end
  end

  describe "upload_date/1" do
    test "reads the date out of the millisecond timestamp" do
      assert Fix.upload_date("uploads/#{@hash}_1611047725444_Report.pdf") == "2021-01-19"
      assert Fix.upload_date("uploads/1611047725444_Report.pdf") == "2021-01-19"
    end

    test "is nil without a timestamp" do
      assert Fix.upload_date("uploads/Report.pdf") == nil
    end
  end
end
