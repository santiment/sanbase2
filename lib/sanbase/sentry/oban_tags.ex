defmodule Sanbase.Sentry.ObanTags do
  @moduledoc ~s"""
  Promote the interesting Oban job args to Sentry tags.

  The Sentry Oban integration puts the whole `job.args` map into the event's
  `extra` data. `extra` is not searchable and is not part of the tag breakdown of
  an issue, so when hundreds of events are grouped under a single issue there is no
  way to tell *which* entities are failing without opening the events one by one.

  The args listed in `@args_to_tags` are promoted to Sentry tags. This makes them
  searchable (`oban_query_id:667`) and lists all the affected ids in the tag
  breakdown of the issue.

  Call `put_job_context/1` in the beginning of `perform/1`. The Sentry context is
  stored in the process dictionary and Oban runs the job and emits the
  `[:oban, :job, :exception]` telemetry event (the one the Sentry integration
  hooks into) in the same process, so the tags end up in the reported event.
  """

  # The args that identify a row in postgres. Keep the list short - every tag is
  # indexed by Sentry and high-cardinality tags are not free.
  @args_to_tags ["query_id", "dashboard_id", "user_id"]

  @spec put_job_context(Oban.Job.t() | map()) :: :ok
  def put_job_context(job) do
    job |> from_job() |> Sentry.Context.set_tags_context()
  end

  @spec from_job(Oban.Job.t() | map()) :: map()
  def from_job(%{args: args}) when is_map(args) do
    for key <- @args_to_tags, value = Map.get(args, key), into: %{} do
      {:"oban_#{key}", to_string(value)}
    end
  end

  def from_job(_job), do: %{}
end
