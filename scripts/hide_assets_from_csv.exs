# Hide projects listed in a CSV file (sets `is_hidden: true`).
#
# DRY RUN BY DEFAULT — nothing is written unless `--yes` is passed (or
# `yes: true` when called from iex).
#
# Runs in two phases: the CSV is fully validated first, and projects are only
# updated if validation passes — a bad file touches no rows.
#
# The CSV MUST have a header row containing a `slug` column. Any other columns
# are ignored, except an optional `hidden_reason` column, whose value is written
# to the project's `hidden_reason` field when non-empty.
#
# Validation errors (abort before any DB access):
#   - file missing / empty / no data rows after the header
#   - header has no `slug` column
#   - a row with a different number of fields than the header
#   - a row with an empty `slug` value
#
# Validation warnings (do not abort):
#   - duplicate slugs — processed once
#
# Update phase behavior:
#   - if no project exists for a slug, report PROJECT_MISSING and continue
#   - already hidden projects are skipped (idempotent); `hidden_since` is set
#     by Project.changeset/2 only when `is_hidden` flips to true
#
# Two ways to run:
#
#   1. As a script — an optional path argument overrides ./assets_to_hide.csv:
#        mix run scripts/hide_assets_from_csv.exs                    # dry run
#        mix run scripts/hide_assets_from_csv.exs --yes              # apply
#        mix run scripts/hide_assets_from_csv.exs /path/to/file.csv --yes
#
#   2. Paste into iex:
#        Paste the whole `defmodule ... end` block, then call:
#        HideAssetsFromCsv.run()                                     # dry run
#        HideAssetsFromCsv.run("assets_to_hide.csv", yes: true)      # apply
#
#      Validate only, without any DB access:
#        HideAssetsFromCsv.validate("assets_to_hide.csv")

defmodule HideAssetsFromCsv do
  import Ecto.Query

  alias Sanbase.Project
  alias Sanbase.Repo

  @default_path "assets_to_hide.csv"

  @doc ~s"""
  The CSV path used when none is given.
  """
  def default_path(), do: @default_path

  @doc ~s"""
  Validate the CSV, then hide every project listed in it.

  Options:
    * `:yes` (boolean, default `false`) - actually write. When `false`, the run
      is a dry run: the CSV is validated and the projects are looked up, but no
      project is updated.
  """
  def run(path \\ @default_path, opts \\ []) do
    yes? = Keyword.get(opts, :yes, false)

    case validate(path) do
      {:ok, %{rows: rows}} ->
        rows
        |> hide_projects(yes?)
        |> print_hide_report(path, yes?)

      {:error, errors} ->
        IO.puts("\nAborted — no project was updated. Fix the CSV and run again.")
        {:error, errors}
    end
  end

  @doc ~s"""
  Validate the CSV without touching the database.

  Returns `{:ok, %{rows: rows, warnings: warnings}}` with the deduplicated rows,
  or `{:error, errors}`. Prints a report either way.
  """
  def validate(path \\ @default_path) do
    IO.puts("\n=== Validating #{path} ===")

    with {:ok, parsed} <- parse_csv(path),
         {:ok, header} <- validate_header(parsed),
         {:ok, slug_index, reason_index} <- column_indices(header),
         rows = build_rows(parsed, slug_index, reason_index),
         :ok <- validate_rows(rows, length(header)) do
      print_validation_ok(rows, length(header), reason_index)
    else
      {:error, errors} ->
        Enum.each(errors, fn error -> IO.puts("ERROR: #{error}") end)
        {:error, errors}
    end
  end

  defp print_validation_ok(rows, column_count, reason_index) do
    {unique_rows, warnings} = dedup_rows(rows)

    IO.puts("OK: #{column_count} columns, #{length(rows)} data rows, `slug` column found")
    if reason_index, do: IO.puts("OK: optional `hidden_reason` column found")
    Enum.each(warnings, fn warning -> IO.puts("WARNING: #{warning}") end)

    {:ok, %{rows: unique_rows, warnings: warnings}}
  end

  ## Validation

  defp parse_csv(path) do
    case File.read(path) do
      {:ok, contents} ->
        {:ok, NimbleCSV.RFC4180.parse_string(contents, skip_headers: false)}

      {:error, reason} ->
        {:error, ["cannot read #{inspect(Path.expand(path))}: #{:file.format_error(reason)}"]}
    end
  rescue
    e in NimbleCSV.ParseError ->
      {:error, ["malformed CSV: #{Exception.message(e)}"]}
  end

  defp validate_header([]),
    do: {:error, ["the file is empty — a header row with a `slug` column is required"]}

  defp validate_header([_header]),
    do: {:error, ["the file has only a header row — no data rows to process"]}

  defp validate_header([header | _data_rows]), do: {:ok, Enum.map(header, &normalize_header/1)}

  # Strip a UTF-8 BOM from the first header cell and normalize casing/spacing
  defp normalize_header(field) do
    field
    |> String.replace_prefix("﻿", "")
    |> String.trim()
    |> String.downcase()
  end

  defp column_indices(header) do
    case Enum.find_index(header, &(&1 == "slug")) do
      nil ->
        {:error, ["the header has no `slug` column. Header: #{inspect(header)}"]}

      slug_index ->
        {:ok, slug_index, Enum.find_index(header, &(&1 == "hidden_reason"))}
    end
  end

  # Row numbers count data rows only — `row 1` is the first row after the header
  defp build_rows([_header | data_rows], slug_index, reason_index) do
    data_rows
    |> Enum.with_index(1)
    |> Enum.map(fn {row, row_number} ->
      %{
        row_number: row_number,
        field_count: length(row),
        slug: row |> Enum.at(slug_index) |> to_trimmed_string(),
        hidden_reason: reason_index && row |> Enum.at(reason_index) |> to_trimmed_string()
      }
    end)
  end

  defp to_trimmed_string(nil), do: ""
  defp to_trimmed_string(value), do: String.trim(value)

  defp validate_rows(rows, header_field_count) do
    ragged =
      rows
      |> Enum.reject(fn row -> row.field_count == header_field_count end)
      |> Enum.map(fn row ->
        "row #{row.row_number} has #{row.field_count} fields, the header has #{header_field_count}"
      end)

    blank =
      rows
      |> Enum.filter(fn row -> row.slug == "" end)
      |> Enum.map(fn row -> "row #{row.row_number} has an empty `slug` value" end)

    case ragged ++ blank do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp dedup_rows(rows) do
    unique_rows = Enum.uniq_by(rows, fn row -> row.slug end)

    warnings =
      case length(rows) - length(unique_rows) do
        0 ->
          []

        count ->
          duplicates =
            rows
            |> Enum.frequencies_by(fn row -> row.slug end)
            |> Enum.filter(fn {_slug, freq} -> freq > 1 end)
            |> Enum.map_join(", ", fn {slug, freq} -> "#{slug} (x#{freq})" end)

          ["#{count} duplicate row(s), processed once each: #{duplicates}"]
      end

    {unique_rows, warnings}
  end

  ## Update phase

  defp hide_projects(rows, yes?) do
    projects_by_slug = rows |> Enum.map(fn row -> row.slug end) |> projects_by_slug()

    Enum.map(rows, &process_row(&1, projects_by_slug, yes?))
  end

  defp projects_by_slug(slugs) do
    from(p in Project, where: p.slug in ^slugs)
    |> Repo.all()
    |> Map.new(fn project -> {project.slug, project} end)
  end

  defp process_row(%{slug: slug} = row, projects_by_slug, yes?) do
    case Map.get(projects_by_slug, slug) do
      nil ->
        %{status: :project_missing, slug: slug}

      %Project{is_hidden: true} = project ->
        %{status: :skipped, slug: slug, project_id: project.id}

      %Project{} = project when yes? ->
        update_project(project, row)

      %Project{} = project ->
        %{status: :would_hide, slug: slug, project_id: project.id}
    end
  end

  defp update_project(%Project{} = project, %{slug: slug, hidden_reason: hidden_reason}) do
    attrs = %{is_hidden: true}

    attrs =
      if hidden_reason in [nil, ""],
        do: attrs,
        else: Map.put(attrs, :hidden_reason, hidden_reason)

    project
    |> Project.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, project} -> %{status: :hidden, slug: slug, project_id: project.id}
      {:error, changeset} -> %{status: :errored, slug: slug, error: inspect(changeset.errors)}
    end
  end

  ## Reporting

  defp print_hide_report(results, path, yes?) do
    mode = if yes?, do: "APPLY", else: "DRY RUN"
    IO.puts("\n=== Hide assets from #{path} [#{mode}] ===")

    Enum.each(results, fn r -> IO.puts(format_result(r)) end)

    summary = summarize(results)

    summary_line =
      [:hidden, :would_hide, :skipped, :project_missing, :errored]
      |> Enum.map_join(" ", fn k -> "#{k}=#{Map.get(summary, k, 0)}" end)

    IO.puts("\nSummary: #{summary_line}")

    unless yes? do
      IO.puts("\nDry run — nothing was written. Re-run with --yes to apply.")
    end

    %{results: results, summary: summary, dry_run?: not yes?}
  end

  defp summarize(results) do
    Enum.reduce(results, %{}, fn %{status: status}, acc ->
      Map.update(acc, status, 1, &(&1 + 1))
    end)
  end

  defp pad(s, n), do: String.pad_trailing(to_string(s), n)

  defp format_result(%{status: :hidden, slug: s, project_id: pid}),
    do: "HIDDEN           #{pad(s, 30)} project_id=#{pid}"

  defp format_result(%{status: :would_hide, slug: s, project_id: pid}),
    do: "WOULD_HIDE       #{pad(s, 30)} project_id=#{pid}"

  defp format_result(%{status: :skipped, slug: s, project_id: pid}),
    do: "SKIP             #{pad(s, 30)} project_id=#{pid} (already hidden)"

  defp format_result(%{status: :project_missing, slug: s}),
    do: "PROJECT_MISSING  #{pad(s, 30)} (no project for slug)"

  defp format_result(%{status: :errored, slug: s, error: error}),
    do: "ERROR            #{pad(s, 30)} #{error}"
end

# When loaded via `mix run`, kick it off: dry run unless --yes is passed, with
# an optional CSV path as the first positional argument. In iex, paste the
# `defmodule ... end` block above and call HideAssetsFromCsv.run/2 yourself
# (this block is harmless to paste too — it runs a dry run once).
argv = System.argv()

path =
  Enum.find(argv, HideAssetsFromCsv.default_path(), fn arg ->
    not String.starts_with?(arg, "-")
  end)

HideAssetsFromCsv.run(path, yes: "--yes" in argv)
