defmodule Sanbase.DeepResearch.Failure do
  @moduledoc """
  A failed call to the research agent, in the two shapes the rest of the stack
  needs.

    * `:message` — what the turn is persisted with and what the research UI
      shows. That UI is admin-only, so the message names the call, the agent's
      URL and the reason: an agent nobody can reach should read as one, instead
      of being guessed at from the timing of a bare `"timeout"`.

    * `:resumable?` — whether the run is worth picking back up. A connection that
      timed out, was refused or dropped says nothing about the research itself:
      the thread and the work already on it live on the agent side, so the turn
      is parked `:paused` and Continue resumes it. An answer FROM the agent (an
      HTTP status) or a call we refused to make is not fixed by retrying, and
      settles the turn `:failed`.

  Constructed by `Sanbase.DeepResearch.Client` (which knows the call and the
  URL); consumed by `Sanbase.DeepResearch.Runner.fail_run/2`.
  """

  defstruct [:message, resumable?: false]

  @type t :: %__MODULE__{message: String.t(), resumable?: boolean()}

  @retry_hint "Nothing was lost — Continue retries the turn."

  @doc """
  `operation` against `url` never got an answer: DNS, connect or read failed.
  Resumable — nothing on the agent side went wrong, we just could not talk to it.

  `operation` is read inside parentheses, so name the call as a noun:
  `"create_thread"`, `"the research stream"`.
  """
  @spec connection(String.t(), String.t(), Exception.t() | term()) :: t()
  def connection(operation, url, error) do
    %__MODULE__{
      message:
        "Connection to the research agent failed: #{reason(error)} " <>
          "(#{operation}, #{url}). #{@retry_hint}",
      resumable?: true
    }
  end

  @doc """
  The agent answered `operation` with a status we cannot use. Not resumable: the
  same call gets the same answer until someone changes the agent's side.

  `operation` opens the sentence — `"create_thread failed (HTTP 401): ..."`.
  """
  @spec response(String.t(), non_neg_integer(), term()) :: t()
  def response(operation, status, body \\ nil) do
    %__MODULE__{message: "#{operation} failed (HTTP #{status})#{explain(status, body)}"}
  end

  @doc """
  Our side stopped mid-run — the stream task crashed, an unexpected exception.
  Resumable for the same reason a lost connection is: the agent kept working and
  the thread is still there.
  """
  @spec crashed(term()) :: t()
  def crashed(reason) do
    %__MODULE__{
      message: "The research run stopped unexpectedly: #{describe(reason)}. #{@retry_hint}",
      resumable?: true
    }
  end

  @doc "The call was never made — a misconfiguration only a human can clear."
  @spec refused(String.t()) :: t()
  def refused(message), do: %__MODULE__{message: message}

  # Transport reasons arrive as `%Req.TransportError{reason: atom}` and carry a
  # one-word message ("timeout", "closed") that reads as nothing in the UI. Name
  # what each one means for whoever has to fix it.
  defp reason(%{reason: :timeout}), do: "the request timed out"
  defp reason(%{reason: :econnrefused}), do: "connection refused, nothing is listening there"
  defp reason(%{reason: :closed}), do: "the connection closed mid-request"
  defp reason(%{reason: :econnreset}), do: "the connection was reset"
  defp reason(%{reason: :nxdomain}), do: "the host could not be resolved (DNS)"

  defp reason(%{reason: unreachable}) when unreachable in [:ehostunreach, :enetunreach],
    do: "the host is unreachable from this network (VPN?)"

  defp reason(%{__exception__: true} = error), do: Exception.message(error)
  defp reason(other), do: inspect(other)

  defp explain(status, _body) when status in [401, 403],
    do: ": the agent rejected our credentials — check its auth token (DRA_AUTH_TOKEN)."

  defp explain(404, _body), do: ": the agent has no such thread — start a new session."

  defp explain(status, body) when status >= 500,
    do: ": the agent itself errored." <> summarize(body)

  defp explain(_status, body), do: "." <> summarize(body)

  # Bodies range from a plain string to a decoded map to nothing at all, and a
  # stack trace from the agent would swamp the UI.
  defp summarize(nil), do: ""
  defp summarize(""), do: ""
  defp summarize(body) when is_binary(body), do: " " <> String.slice(body, 0, 300)
  defp summarize(body), do: " " <> (body |> inspect() |> String.slice(0, 300))

  defp describe(%{__exception__: true} = error), do: Exception.message(error)
  defp describe(reason), do: inspect(reason)
end
