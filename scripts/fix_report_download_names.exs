# Give already uploaded reports a clean file name.
#
# Report objects sit in S3 under a key prefixed with the content hash and the
# upload timestamp - `uploads/<hash>_<millis>_Santiment_Report.pdf` - and that
# is what browsers name the downloaded file. New uploads are fine, they get a
# content-disposition header from `Sanbase.FileStore.s3_object_headers/2`. This
# fixes the older ones by copying each object to a clean key and pointing the
# `reports` row at the copy.
#
# ## Usage
#
#     mix run --no-start scripts/fix_report_download_names.exs [options]
#
#     --force        apply the plan. Without it nothing is written anywhere.
#     --verify       hash the real bytes instead of reading the hash off the
#                    key. Read-only, downloads every object, slow.
#     --diagnose     print credentials, buckets and raw S3 probe errors, then
#                    stop. Start here when nothing can be read.
#     --id=<id>      one report.
#     --search=<s>   reports whose name or url contains <s>.
#
#     DATABASE_URL=... POSTS_IMAGE_BUCKET=... \
#     REPORTS_AWS_ACCESS_KEY_ID=... REPORTS_AWS_SECRET_ACCESS_KEY=... \
#     mix run --no-start scripts/fix_report_download_names.exs
#
# `--no-start` matters: plain `mix run` boots Oban, the alert scheduler and the
# web endpoint, which must not happen from a local machine pointed at a remote
# database. Only Postgres and the S3 client are started.
#
# `REPORTS_AWS_*`, not `AWS_*`. config/runtime.exs loads .env files through
# Sanbase.EnvConfigLoader, whose load_line/1 calls System.put_env
# unconditionally, so a line like `AWS_ACCESS_KEY_ID=""` in .env.dev overwrites
# what you export on the command line. REPORTS_AWS_REGION overrides the region,
# otherwise hardcoded to eu-central-1 in config/config.exs.
#
# ## Nothing can be lost
#
# There is no S3 delete in this file. The source object is never modified and
# stays readable on its old url. An existing object is never overwritten - the
# destination is checked with HEAD and the copy is sent with `if-none-match: *`.
# The database is written only after the copy is verified byte for byte, and
# every change prints `<old url> -> <new url>` so it can be reverted.
#
# ## Clashing names
#
# Reports uploaded under the same original file name all want the same clean
# key, so every member of such a group gets its upload date appended:
#
#     af5bfb1f..._1611047725444_Santiment Weekly Pro Report.pdf
#       -> Santiment Weekly Pro Report 2021-01-19.pdf
#
# Names are compared case-insensitively. If the date does not separate a group
# either, the whole group is skipped and listed under the table.

defmodule FixReportDownloadNames do
  alias Sanbase.FileStore
  alias Sanbase.Utils.FileHash

  @statuses %{
    ready: "will copy",
    dest_exists: "dest exists - verify",
    dest_same: "dest is same file - repoint",
    dest_differs: "COLLISION in s3 - skip",
    hash_mismatch: "hash mismatch - skip",
    batch_collision: "COLLISION with another report - skip",
    already_clean: "already clean - skip",
    source_missing: "source missing in s3 - skip",
    read_failed: "s3 read failed - skip",
    no_url: "no url - skip"
  }

  @applicable [:ready, :dest_exists, :dest_same]
  @detail_limit 5

  def run(opts \\ []) do
    ensure_started!()
    bucket = bucket()
    verify? = Keyword.get(opts, :verify, false)

    IO.puts("Database: #{database_description()}")
    IO.puts("Bucket: #{bucket}")
    if verify?, do: IO.puts("Verifying - every object is downloaded and hashed, which is slow.")

    all_reports = Sanbase.Report.list_reports()
    IO.puts("Reports in the database: #{length(all_reports)}")

    if Keyword.get(opts, :diagnose, false) do
      diagnose(all_reports, bucket)
      throw(:diagnosed)
    end

    resolved = resolve_keys(all_reports, bucket)

    plan =
      opts
      |> select_reports(all_reports)
      |> Enum.map(&plan_row(&1, verify?, resolved))

    print_table(plan, verify?)
    print_details(plan)
    print_buckets(plan, bucket)
    print_notes(plan)
    print_collisions(resolved)
    print_summary(plan, all_reports)

    if Keyword.get(opts, :force, false) do
      IO.puts("\nApplying:\n")
      plan |> Enum.filter(&(&1.status in @applicable)) |> Enum.each(&apply_row/1)
    else
      count = Enum.count(plan, &(&1.status in @applicable))
      IO.puts("\nDry run - nothing written. Re-run with --force to apply #{count} change(s).")
    end
  end

  # Selecting

  defp select_reports(opts, all_reports) do
    all_reports
    |> sort_reports()
    |> filter_by_id(Keyword.get(opts, :id))
    |> filter_by_search(Keyword.get(opts, :search))
  end

  # `list_reports/0` is a bare `Repo.all/1` with no ORDER BY. The getReports API
  # orders by inserted_at desc, id desc - matching it lets the two be compared.
  defp sort_reports(reports) do
    Enum.sort(reports, fn a, b ->
      case compare_timestamps(a.inserted_at, b.inserted_at) do
        :gt -> true
        :lt -> false
        :eq -> a.id >= b.id
      end
    end)
  end

  defp compare_timestamps(nil, nil), do: :eq
  defp compare_timestamps(nil, _b), do: :lt
  defp compare_timestamps(_a, nil), do: :gt
  defp compare_timestamps(a, b), do: NaiveDateTime.compare(a, b)

  defp filter_by_id(reports, nil), do: reports

  defp filter_by_id(reports, id) do
    [Enum.find(reports, &(&1.id == id)) || raise("No report with id #{id}")]
  end

  defp filter_by_search(reports, nil), do: reports

  defp filter_by_search(reports, term) do
    term = String.downcase(term)

    case Enum.filter(reports, &matches?(&1, term)) do
      [] -> raise("No report matching #{inspect(term)}")
      matched -> matched
    end
  end

  defp matches?(report, term) do
    [report.name, report.url]
    |> Enum.reject(&is_nil/1)
    |> Enum.any?(&String.contains?(String.downcase(&1), term))
  end

  # Planning

  # Works out the destination key for every report at once, because collision
  # detection has to see reports that `--id` and `--search` filtered out.
  # Returns the per-report entries and the names a date could not separate.
  defp resolve_keys(all_reports, bucket) do
    entries =
      all_reports
      |> Enum.reject(&is_nil(&1.url))
      |> Enum.map(fn report ->
        {report_bucket, old_key} = bucket_and_key(report.url, bucket)
        %{id: report.id, bucket: report_bucket, old_key: old_key, base: clean_key(old_key)}
      end)

    colliding = colliding_names(entries, & &1.base)

    entries =
      Enum.map(entries, fn entry ->
        new_key =
          cond do
            # Already on its clean key - it keeps it, the others move aside.
            entry.old_key == entry.base -> entry.base
            MapSet.member?(colliding, downcase(entry.base)) -> dated_key(entry)
            true -> entry.base
          end

        Map.put(entry, :new_key, new_key)
      end)

    {Map.new(entries, &{&1.id, &1}), colliding_names(entries, & &1.new_key)}
  end

  # Two rows resolving to one name from the same source object are the same file
  # recorded twice, not a clash.
  defp colliding_names(entries, key_fun) do
    entries
    |> Enum.group_by(&(&1 |> key_fun.() |> downcase()), & &1.old_key)
    |> Enum.filter(fn {name, keys} -> not is_nil(name) and length(Enum.uniq(keys)) > 1 end)
    |> Enum.map(fn {name, _keys} -> name end)
    |> MapSet.new()
  end

  defp clean_key(old_key) do
    Path.join(Path.dirname(old_key), FileStore.download_filename(old_key))
  end

  defp dated_key(entry) do
    case upload_date(entry.old_key) do
      nil -> nil
      date -> Path.rootname(entry.base) <> " " <> date <> Path.extname(entry.base)
    end
  end

  defp upload_date(old_key) do
    case Regex.run(~r/^(?:[0-9a-fA-F]{32,}_)?(\d{13})_/, Path.basename(old_key)) do
      [_, millis] ->
        millis
        |> String.to_integer()
        |> DateTime.from_unix!(:millisecond)
        |> DateTime.to_date()
        |> Date.to_string()

      nil ->
        nil
    end
  end

  defp plan_row(%Sanbase.Report{url: nil} = report, _verify?, _resolved) do
    %{
      report: report,
      bucket: nil,
      old_key: nil,
      new_key: nil,
      hash: nil,
      status: :no_url,
      note: nil
    }
  end

  defp plan_row(%Sanbase.Report{} = report, verify?, {keys, unresolved}) do
    entry = Map.fetch!(keys, report.id)

    row = %{
      report: report,
      bucket: entry.bucket,
      old_key: entry.old_key,
      new_key: entry.new_key,
      hash: hash_from_key(entry.old_key),
      status: nil,
      note: nil
    }

    {status, note} = with_note(status(row, unresolved))
    row = %{row | status: status, note: note}

    if verify?, do: verify_row(row), else: row
  end

  defp with_note({status, note}), do: {status, note}
  defp with_note(status), do: {status, nil}

  defp status(%{new_key: nil}, _unresolved), do: :batch_collision
  defp status(%{old_key: key, new_key: key}, _unresolved), do: :already_clean

  defp status(row, unresolved) do
    if MapSet.member?(unresolved, downcase(row.new_key)),
      do: :batch_collision,
      else: source_status(row)
  end

  # The source is checked first: a row can outlive the object it points at, and
  # copying a missing object would fail confusingly at apply time.
  defp source_status(row) do
    case head_object(row.bucket, row.old_key) do
      {:ok, _headers} -> destination_status(row.bucket, row.new_key)
      {:error, {:http_error, 404, _}} -> :source_missing
      {:error, error} -> {:read_failed, describe_error(error)}
    end
  end

  defp destination_status(bucket, new_key) do
    case head_object(bucket, new_key) do
      {:error, {:http_error, 404, _}} -> :ready
      {:ok, _headers} -> :dest_exists
      {:error, error} -> {:read_failed, describe_error(error)}
    end
  end

  # --verify: hash what is really stored rather than trusting the key name.
  defp verify_row(%{status: status} = row) when status not in @applicable, do: row

  defp verify_row(row) do
    case download_and_hash(row.bucket, row.old_key) do
      {:error, _error} ->
        %{row | status: :read_failed, note: "download failed"}

      {:ok, hash} ->
        key_hash = hash_from_key(row.old_key)
        row = %{row | hash: hash}

        cond do
          key_hash not in [nil, hash] -> %{row | status: :hash_mismatch}
          row.status == :dest_exists -> classify_destination(row, hash)
          true -> row
        end
    end
  end

  # Tells a resumable copy from an earlier run apart from a real name clash.
  defp classify_destination(row, source_hash) do
    case download_and_hash(row.bucket, row.new_key) do
      {:ok, ^source_hash} -> %{row | status: :dest_same}
      {:ok, _other} -> %{row | status: :dest_differs}
      {:error, _error} -> %{row | status: :read_failed, note: "download failed"}
    end
  end

  # Applying

  defp apply_row(%{report: %Sanbase.Report{id: id} = report} = row) do
    %{bucket: bucket, old_key: old, new_key: new} = row

    with :ok <- ensure_destination_free(id, bucket, old, new),
         :ok <- verify_copy(id, bucket, old, new) do
      repoint(report, new)
    end
  end

  # The HEAD is redone here rather than reusing the plan, so the decision is
  # made on current state.
  defp ensure_destination_free(id, bucket, old_key, new_key) do
    case head_object(bucket, new_key) do
      {:error, {:http_error, 404, _}} ->
        copy(id, bucket, old_key, new_key)

      {:ok, _headers} ->
        log(id, "destination exists: #{new_key} - verifying it is the same file")
        :ok

      {:error, error} ->
        log(id, "aborted - could not HEAD #{new_key}: #{inspect(error)}")
        :error
    end
  end

  # `metadata_directive: :REPLACE` applies to the COPY, never to the source. It
  # is what lets the copy carry its own content-disposition.
  defp copy(id, bucket, old_key, new_key) do
    headers =
      case head_object(bucket, old_key) do
        {:ok, headers} -> headers
        {:error, _error} -> []
      end

    opts =
      [
        metadata_directive: :REPLACE,
        content_disposition: FileStore.content_disposition(new_key),
        content_type: get_header(headers, "content-type"),
        cache_control: get_header(headers, "cache-control"),
        acl: :public_read,
        # S3 answers 412 instead of overwriting. Drop it if the backend does not
        # support conditional writes - the HEAD above still guards, less tightly.
        if_none_match: "*"
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    ExAws.S3.put_object_copy(bucket, new_key, bucket, old_key, opts)
    |> ExAws.request()
    |> case do
      {:ok, _response} ->
        log(id, "copied #{old_key} -> #{new_key}")
        :ok

      {:error, {:http_error, 412, _}} ->
        log(id, "aborted - #{new_key} was taken by a concurrent write, nothing changed")
        :error

      {:error, error} ->
        log(id, "aborted - copy failed: #{inspect(error)}")
        :error
    end
  end

  # Both objects are downloaded and compared, rather than trusting the hash in
  # the key or an ETag, which a server side copy does not preserve.
  defp verify_copy(id, bucket, old_key, new_key) do
    with {:ok, source_hash} <- download_and_hash(bucket, old_key),
         {:ok, dest_hash} <- download_and_hash(bucket, new_key) do
      key_hash = hash_from_key(old_key)

      cond do
        source_hash != dest_hash ->
          log(id, "NOT REPOINTED - #{new_key} differs from the source. Name collision, or a")
          log(id, "  bad copy from an earlier run. Nothing was overwritten, nothing deleted")
          log(id, "  source #{source_hash}")
          log(id, "  copy   #{dest_hash}")
          :error

        key_hash not in [nil, source_hash] ->
          log(id, "NOT REPOINTED - #{old_key} does not hash to the hash in its own name")
          :error

        true ->
          log(id, "verified sha256 #{source_hash}")
          :ok
      end
    else
      {:error, error} ->
        log(id, "NOT REPOINTED - could not verify: #{inspect(error)}")
        :error
    end
  end

  defp download_and_hash(bucket, key) do
    path = Path.join(System.tmp_dir!(), "report-verify-#{System.unique_integer([:positive])}")

    try do
      case ExAws.S3.download_file(bucket, key, path) |> ExAws.request() do
        {:ok, _response} -> FileHash.calculate(path)
        {:error, error} -> {:error, error}
      end
    after
      File.rm(path)
    end
  end

  defp repoint(%Sanbase.Report{id: id, url: old_url} = report, new_key) do
    new_url = build_url(old_url, new_key)

    case Sanbase.Report.update(report, %{url: new_url}) do
      {:ok, _report} -> log(id, "REPOINTED #{old_url} -> #{new_url}")
      {:error, error} -> log(id, "copy is fine but the url update failed: #{inspect(error)}")
    end
  end

  # Output

  defp print_table(plan, verify?) do
    hash_header = if verify?, do: "sha256 (downloaded)", else: "sha256 (from key)"
    header = ["id", "inserted_at", "status", hash_header, "old name (hash elided)", "new name"]

    rows =
      Enum.map(plan, fn row ->
        [
          to_string(row.report.id),
          format_timestamp(row.report.inserted_at),
          Map.fetch!(@statuses, row.status),
          abbrev_hash(row.hash),
          row.old_key |> basename() |> elide_hash(),
          basename(row.new_key)
        ]
      end)

    widths =
      [header | rows]
      |> Enum.zip_with(fn column -> column |> Enum.map(&String.length/1) |> Enum.max() end)

    IO.puts("Keys are all under #{directory(plan)}, only the file names are shown.\n")
    IO.puts(format_row(header, widths))
    IO.puts(widths |> Enum.map(&String.duplicate("-", &1)) |> Enum.join("-+-"))
    Enum.each(rows, &IO.puts(format_row(&1, widths)))
  end

  # Full urls would make the table unreadable, but a narrow selection means one
  # report was looked up and the urls are the point.
  defp print_details(plan) when length(plan) > @detail_limit, do: :ok

  defp print_details(plan) do
    Enum.each(plan, fn row ->
      IO.puts("\n== report #{row.report.id} ==")
      IO.puts("  name:        #{row.report.name}")
      IO.puts("  inserted_at: #{format_timestamp(row.report.inserted_at)}")
      IO.puts("  status:      #{Map.fetch!(@statuses, row.status)}")
      IO.puts("  url:         #{row.report.url}")

      if row.old_key do
        IO.puts("  bucket:      #{row.bucket}")
        IO.puts("  key:         #{row.old_key}")
      end

      if row.new_key && row.new_key != row.old_key do
        IO.puts("  new key:     #{row.new_key}")
        IO.puts("  new url:     #{build_url(row.report.url, row.new_key)}")
      end
    end)
  end

  # A row uploaded years ago can live in a different bucket than the env var
  # names today. The url wins.
  defp print_buckets(plan, env_bucket) do
    buckets = plan |> Enum.map(& &1.bucket) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    case buckets -- [env_bucket] do
      [] ->
        :ok

      others ->
        IO.puts("\nBuckets taken from the stored urls, which differ from POSTS_IMAGE_BUCKET")
        IO.puts("(#{env_bucket}): #{Enum.join(others, ", ")}")
        IO.puts("The url is authoritative - reads and copies use the bucket named there.")
    end
  end

  # Once per distinct reason, with one worked example. If the key looks wrong,
  # the problem is the parsing rather than the credentials.
  defp print_notes(plan) do
    plan
    |> Enum.reject(&is_nil(&1.note))
    |> Enum.group_by(& &1.note)
    |> Enum.each(fn {note, rows} ->
      example = Enum.min_by(rows, & &1.report.id)

      IO.puts("\n#{note}")

      IO.puts(
        "  reports:   #{rows |> Enum.map(& &1.report.id) |> Enum.sort() |> Enum.join(", ")}"
      )

      IO.puts("  url:       #{example.report.url}")
      IO.puts("  key tried: #{example.old_key}")
    end)
  end

  # Only groups the upload date could not separate - the rest need no attention.
  defp print_collisions({keys, unresolved}) do
    groups =
      keys
      |> Map.values()
      |> Enum.filter(fn entry ->
        is_nil(entry.new_key) or MapSet.member?(unresolved, downcase(entry.new_key))
      end)
      |> Enum.group_by(fn entry -> entry.new_key || entry.base end)

    if groups != %{} do
      IO.puts("\nUnresolved collisions - one clean name wanted by more than one object, and")
      IO.puts("the upload date did not separate them. None of these are touched.\n")

      groups
      |> Enum.sort()
      |> Enum.each(fn {name, entries} ->
        IO.puts("  #{Path.basename(name)}")

        entries
        |> Enum.sort_by(& &1.id)
        |> Enum.each(fn entry ->
          IO.puts("    report #{entry.id} - #{entry.old_key |> Path.basename() |> elide_hash()}")
        end)
      end)
    end
  end

  # A table too long to read at once can still be checked for completeness. The
  # counts differ only when --id or --search was used.
  defp print_summary(plan, all_reports) do
    IO.puts("\n#{length(plan)} row(s) in the table, #{length(all_reports)} in the database.")

    plan
    |> Enum.frequencies_by(& &1.status)
    |> Enum.sort_by(fn {_status, count} -> -count end)
    |> Enum.each(fn {status, count} ->
      IO.puts("  #{String.pad_trailing(Map.fetch!(@statuses, status), 38)} #{count}")
    end)
  end

  defp format_row(cells, widths) do
    cells
    |> Enum.zip(widths)
    |> Enum.map(fn {cell, width} -> String.pad_trailing(cell, width) end)
    |> Enum.join(" | ")
    |> String.trim_trailing()
  end

  defp directory(plan) do
    Enum.find_value(plan, "uploads", fn row -> row.old_key && Path.dirname(row.old_key) end)
  end

  defp format_timestamp(nil), do: "-"
  defp format_timestamp(at), do: at |> NaiveDateTime.to_string() |> String.slice(0, 16)

  defp basename(nil), do: "-"
  defp basename(key), do: Path.basename(key)

  defp elide_hash(name) do
    String.replace(name, ~r/^([0-9a-fA-F]{8})[0-9a-fA-F]{24,}_/, "\\1..._")
  end

  defp abbrev_hash(nil), do: "-"
  defp abbrev_hash(hash), do: String.slice(hash, 0, 8) <> "..." <> String.slice(hash, -8, 8)

  defp log(id, message), do: IO.puts("[report #{id}] #{message}")

  # Diagnosing

  defp diagnose(all_reports, env_bucket) do
    config = ExAws.Config.new(:s3, Application.get_all_env(:ex_aws))

    IO.puts("\n== credentials ==")
    IO.puts("  region:            #{inspect(config[:region])}")
    IO.puts("  access_key_id:     #{mask(config[:access_key_id])}")
    IO.puts("  secret_access_key: #{mask(config[:secret_access_key])}")

    if blank?(config[:access_key_id]) or blank?(config[:secret_access_key]) do
      IO.puts("""

        The credentials are EMPTY, which is not the same as missing - S3 answers
        400 AuthorizationHeaderMalformed. A line like `AWS_ACCESS_KEY_ID=""` in
        .env.dev overwrites what you export, because EnvConfigLoader.load_line/1
        calls System.put_env unconditionally. Remove it, or pass the credentials
        as REPORTS_AWS_ACCESS_KEY_ID and REPORTS_AWS_SECRET_ACCESS_KEY.
      """)
    end

    urls = all_reports |> Enum.reject(&is_nil(&1.url))
    buckets = urls |> Enum.map(&(&1.url |> bucket_and_key(env_bucket) |> elem(0))) |> Enum.uniq()

    IO.puts("\n== buckets named by the stored urls ==")
    IO.puts("  #{Enum.join(buckets, ", ")}   (POSTS_IMAGE_BUCKET is #{env_bucket})")

    Enum.each(buckets, fn bucket ->
      IO.puts("\n== #{bucket} ==")
      probe("get_bucket_location", ExAws.S3.get_bucket_location(bucket))
      probe("list_objects (needs s3:ListBucket)", ExAws.S3.list_objects(bucket, max_keys: 1))
    end)

    if example = List.first(urls) do
      {bucket, key} = bucket_and_key(example.url, env_bucket)
      IO.puts("\n== head_object on report #{example.id} ==")
      IO.puts("  url:    #{example.url}")
      IO.puts("  bucket: #{bucket}")
      IO.puts("  key:    #{key}")
      probe("head_object", ExAws.S3.head_object(bucket, key))
    end
  end

  defp probe(label, operation) do
    case ExAws.request(operation) do
      {:ok, response} -> IO.puts("  #{label}: ok #{trim(response)}")
      {:error, error} -> IO.puts("  #{label}: FAILED #{trim(error, 400)}")
    end
  end

  defp trim(term, length \\ 120), do: term |> inspect() |> String.slice(0, length)

  defp blank?(value), do: is_nil(value) or value == ""

  defp mask(""), do: "EMPTY (set, but to an empty string)"
  defp mask(nil), do: "MISSING"

  defp mask(value) when is_binary(value) and byte_size(value) > 4,
    do: String.slice(value, 0, 4) <> "... (#{byte_size(value)} chars)"

  defp mask(value), do: inspect(value)

  defp describe_error({:http_error, 403, _response}) do
    "HTTP 403 - the credentials cannot read this key. Either it really is denied, " <>
      "or the object is missing and the credentials lack s3:ListBucket, which makes " <>
      "S3 answer 403 instead of 404"
  end

  defp describe_error({:http_error, code, _response}) when code in [301, 307] do
    "HTTP #{code} - wrong region. ex_aws is set to eu-central-1 in config/config.exs"
  end

  defp describe_error({:http_error, 400, _response}) do
    "HTTP 400 - usually a signing failure: wrong region, or empty credentials"
  end

  defp describe_error({:http_error, code, _response}), do: "HTTP #{code}"
  defp describe_error(error), do: trim(error, 160)

  # S3 and urls

  defp head_object(bucket, key) do
    case ExAws.S3.head_object(bucket, key) |> ExAws.request() do
      {:ok, %{headers: headers}} -> {:ok, headers}
      {:error, error} -> {:error, error}
    end
  end

  defp get_header(headers, name) do
    Enum.find_value(headers, fn {key, value} -> if String.downcase(key) == name, do: value end)
  end

  defp hash_from_key(key) do
    case Regex.run(~r/^([0-9a-fA-F]{64})_/, Path.basename(key)) do
      [_, hash] -> String.downcase(hash)
      nil -> nil
    end
  end

  # Waffle writes one of two url shapes, depending on `virtual_host`:
  #
  #     https://<bucket>.s3.amazonaws.com/uploads/<file name>
  #     https://s3.amazonaws.com/<bucket>/uploads/<file name>
  #
  # Both name the bucket, and the url is the authority on where an object lives
  # - a row uploaded years ago can sit in a bucket POSTS_IMAGE_BUCKET no longer
  # points at.
  defp bucket_and_key(url, fallback_bucket) do
    uri = URI.parse(url)
    path = (uri.path || "") |> String.trim_leading("/") |> URI.decode()

    case String.split(uri.host || "", ".s3", parts: 2) do
      [bucket, _rest] when bucket != "" ->
        {bucket, path}

      _no_bucket_in_host ->
        case String.split(path, "/", parts: 2) do
          [bucket, key] when key != "" -> {bucket, key}
          _no_bucket_in_path -> {fallback_bucket, path}
        end
    end
  end

  defp build_url(old_url, new_key) do
    old_url |> URI.parse() |> Map.put(:path, "/" <> URI.encode(new_key)) |> URI.to_string()
  end

  defp downcase(nil), do: nil
  defp downcase(string), do: String.downcase(string)

  # Booting

  # Only Postgres and the S3 client, so the script can run under `--no-start`.
  defp ensure_started!() do
    Application.load(:sanbase)

    for app <- [:hackney, :ex_aws, :ex_aws_s3, :ex_audit] do
      {:ok, _apps} = Application.ensure_all_started(app)
    end

    apply_credential_overrides()

    case Process.whereis(Sanbase.Repo) do
      nil -> {:ok, _pid} = Sanbase.Repo.start_link(pool_size: 2)
      _pid -> :ok
    end

    :ok
  end

  # These names are not in the .env files, so they survive EnvConfigLoader.
  defp apply_credential_overrides() do
    [
      access_key_id: System.get_env("REPORTS_AWS_ACCESS_KEY_ID"),
      secret_access_key: System.get_env("REPORTS_AWS_SECRET_ACCESS_KEY"),
      region: System.get_env("REPORTS_AWS_REGION")
    ]
    |> Enum.each(fn {key, value} ->
      if is_binary(value) and value != "", do: Application.put_env(:ex_aws, key, value)
    end)
  end

  defp database_description() do
    case System.get_env("DATABASE_URL") do
      nil -> "local, from the Sanbase.Repo config"
      url -> URI.parse(url) |> then(&"#{&1.host}#{&1.port && ":#{&1.port}"}#{&1.path}")
    end
  end

  defp bucket() do
    case Application.fetch_env!(:waffle, :bucket) do
      {:system, env_var} -> System.fetch_env!(env_var)
      bucket when is_binary(bucket) -> bucket
    end
  end
end

{parsed, _argv, _invalid} =
  OptionParser.parse(System.argv(),
    strict: [
      force: :boolean,
      verify: :boolean,
      diagnose: :boolean,
      id: :integer,
      search: :string
    ]
  )

try do
  FixReportDownloadNames.run(parsed)
catch
  :diagnosed -> :ok
end
