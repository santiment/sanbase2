defmodule Sanbase.Sentry.ObanTags do
  @moduledoc ~s"""
  Promote the interesting Oban job args to Sentry tags.

  The Sentry Oban integration puts the whole `job.args` map into the event's
  `extra` data. `extra` is not searchable and is not part of the tag breakdown of
  an issue, so when hundreds of events are grouped under a single issue there is no
  way to tell *which* entities are failing without opening the events one by one.

  The args listed in `@args_to_tags` are promoted to Sentry tags. This makes them
  searchable (`oban_query_id:667`) and lists all the affected ids in the tag
  breakdown of the issue. The list holds only args that identify a row in postgres
  and is kept short - every tag is indexed by Sentry and high-cardinality tags are
  not free. Each tag name is spelled out next to its arg instead of being
  interpolated from it, so that no atoms are created at runtime.

  Call `put_job_context/1` in the beginning of `perform/1`. The Sentry context is
  stored in the logger metadata of the calling process and Oban runs the job and
  emits the `[:oban, :job, :exception]` telemetry event (the one the Sentry
  integration hooks into) from the same process, so the tags end up in the
  reported event.
  """

  @args_to_tags [
    {"query_id", :oban_query_id},
    {"dashboard_id", :oban_dashboard_id},
    {"user_id", :oban_user_id}
  ]

  @doc ~s"""
  Store the tags extracted from the job args as Sentry tags of the calling process.

  ## Examples

      iex> Sanbase.Sentry.ObanTags.put_job_context(%{args: %{"query_id" => 667}})
      :ok
  """
  @spec put_job_context(Oban.Job.t() | map()) :: :ok
  def put_job_context(job) do
    job |> extract_tags_from_job() |> Sentry.Context.set_tags_context()
  end

  @doc ~s"""
  Extract the allowlisted job args as a map of Sentry tag name to string value.

  The args outside of the allowlist, as well as the allowlisted args that are
  missing or `nil`, are not part of the result.

  ## Examples

      iex> Sanbase.Sentry.ObanTags.extract_tags_from_job(%{args: %{"query_id" => 667, "slug" => "bitcoin"}})
      %{oban_query_id: "667"}

      iex> Sanbase.Sentry.ObanTags.extract_tags_from_job(%{args: %{"query_id" => nil}})
      %{}

      iex> Sanbase.Sentry.ObanTags.extract_tags_from_job(%{})
      %{}
  """
  @spec extract_tags_from_job(Oban.Job.t() | map()) :: map()
  def extract_tags_from_job(%{args: args}) when is_map(args) do
    for {key, tag} <- @args_to_tags, value = Map.get(args, key), into: %{} do
      {tag, to_string(value)}
    end
  end

  def extract_tags_from_job(_job), do: %{}
end
