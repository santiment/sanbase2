defmodule SanbaseWeb.DeepResearch.Components do
  @moduledoc """
  Presentation for `SanbaseWeb.DeepResearchLive` — everything from a turn bubble
  down to a single MCP call row, plus the view helpers those components need.

  Only `composer/1` and `turn_view/1` are public; they are the two seams the
  LiveView's own `render/1` reaches for. Everything else is an implementation
  detail of a turn's rendering.

  Nothing here touches the socket or issues events beyond `phx-click`/`phx-submit`
  names, so a component can be rendered in isolation from a plain turn map.
  """
  use SanbaseWeb, :html

  alias Sanbase.DeepResearch.{ReportMarkdown, Timeline}
  alias SanbaseWeb.DeepResearch.ChartRenderer

  attr :query, :string, required: true
  attr :running, :boolean, required: true
  attr :placeholder, :string, required: true

  @doc "The question input: auto-growing textarea plus send / stop buttons."
  def composer(assigns) do
    ~H"""
    <form phx-submit="submit" phx-change="update_query">
      <div class="flex items-end gap-2 rounded-[1.75rem] border border-base-300 bg-base-100 py-1.5 pl-4 pr-2 shadow-sm transition focus-within:border-base-content/25 focus-within:shadow-md">
        <textarea
          id="dr-composer-input"
          name="query"
          rows="1"
          phx-hook="AutoGrow"
          phx-debounce="150"
          disabled={@running}
          placeholder={@placeholder}
          class="max-h-72 min-h-[2.75rem] flex-1 resize-none overflow-y-auto bg-transparent py-2.5 text-[15px] leading-relaxed placeholder:text-base-content/40 focus:outline-none disabled:opacity-60"
        >{@query}</textarea>
        <div class="flex items-center gap-1 pb-1">
          <button
            :if={@running}
            type="button"
            phx-click="cancel"
            aria-label="Stop research"
            class="flex size-9 items-center justify-center rounded-full text-base-content/50 transition hover:bg-base-200 hover:text-error"
          >
            <.icon name="hero-stop" class="size-4" />
          </button>
          <button
            type="submit"
            aria-label="Send"
            disabled={@running or String.trim(@query) == ""}
            class="flex size-9 items-center justify-center rounded-full bg-primary text-primary-content transition hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-30"
          >
            <.icon name="hero-arrow-up" class="size-4" />
          </button>
        </div>
      </div>
    </form>
    """
  end

  attr :turn, :map, required: true
  attr :running, :boolean, required: true

  attr :now_ms, :integer,
    default: nil,
    doc:
      "wall clock for the live elapsed counter; nil for a finished turn, whose own finished_at is authoritative"

  @doc "One question/answer exchange: the asked question, its research timeline, and any error."
  def turn_view(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex justify-end">
        <div class="max-w-[80%] break-words rounded-2xl rounded-br-sm bg-primary px-4 py-2.5 text-sm leading-relaxed text-primary-content">
          {@turn.question}
        </div>
      </div>

      <.research_timeline turn={@turn} running={@running} now_ms={@now_ms} />

      <.clarification_card
        :if={@turn.clarification && @turn.clarification != []}
        questions={@turn.clarification}
      />

      <div
        :if={@turn.error}
        class="flex items-start gap-2 rounded-xl border border-error/30 bg-error/5 px-4 py-3 text-sm text-error"
        role="alert"
      >
        <.icon name="hero-exclamation-triangle" class="mt-0.5 size-4 shrink-0" />
        <span>{@turn.error}</span>
      </div>
    </div>
    """
  end

  attr :questions, :list, required: true

  defp clarification_card(assigns) do
    ~H"""
    <div class="rounded-xl border border-amber-300/50 bg-amber-50/70 p-4 dark:border-amber-500/30 dark:bg-amber-500/10">
      <div class="mb-2 flex items-center gap-2 text-sm font-semibold text-amber-900 dark:text-amber-200">
        <.icon name="hero-question-mark-circle" class="size-4" /> A couple of clarifying questions
      </div>
      <ul class="space-y-1.5 text-sm text-base-content/80">
        <li :for={question <- @questions} class="flex gap-2">
          <span class="mt-2 size-1.5 shrink-0 rounded-full bg-amber-400"></span>
          <span>{question}</span>
        </li>
      </ul>
      <p class="mt-3 text-xs text-base-content/50">Reply below to continue.</p>
    </div>
    """
  end

  attr :turn, :map, required: true
  attr :running, :boolean, required: true
  attr :now_ms, :integer, default: nil

  defp research_timeline(assigns) do
    turn = assigns.turn
    proc_items = visible_items(turn.timeline, turn.report, turn.clarification)
    # A terminal turn has nothing in flight — settle any tool item still marked
    # running so it shows a final state, not a perpetual spinner (e.g. when a run was
    # interrupted before a call returned, like a dev hot-reload killing the workers).
    proc_items =
      if Timeline.terminal_phase?(turn.phase),
        do: Enum.map(proc_items, &settle_item/1),
        else: proc_items

    blocks = Timeline.segment(proc_items)
    has_research = Enum.any?(blocks, &match?({:tools, _, _}, &1)) or not is_nil(turn.report)

    assigns =
      assign(assigns,
        blocks: blocks,
        has_research: has_research,
        empty?: proc_items == [] and is_nil(turn.report)
      )

    ~H"""
    <div :if={not (@empty? and not @running)} class="space-y-3">
      <%= for {block, index} <- Enum.with_index(@blocks) do %>
        <.timeline_block block={block} index={index} turn_id={@turn.id} />
      <% end %>

      <.report_card :if={@turn.report} id={@turn.id} report={@turn.report} />

      <div
        :if={@running}
        class="flex items-center gap-2 text-xs font-medium text-base-content/60"
      >
        <span class="loading loading-spinner loading-xs text-primary"></span>
        {phase_label(@turn.phase)} · {format_duration(elapsed_seconds(@turn, @now_ms))}
      </div>
      <div
        :if={((not @running and @turn.started_at) && @has_research) and @turn.phase == :completed}
        class="flex items-center gap-1.5 text-xs text-base-content/50"
      >
        <.icon name="hero-check-circle" class="size-3.5 text-success" />
        Researched in {format_duration(elapsed_seconds(@turn, @now_ms))}
      </div>
      <div
        :if={@turn.phase == :cancelled and @has_research}
        class="flex items-center gap-1.5 text-xs text-base-content/40"
      >
        <.icon name="hero-no-symbol" class="size-3.5" />
        Stopped after {format_duration(elapsed_seconds(@turn, @now_ms))}
      </div>
    </div>
    """
  end

  attr :block, :any, required: true
  attr :index, :integer, required: true
  attr :turn_id, :any, default: nil

  defp timeline_block(%{block: {:narration, items}} = assigns) do
    assigns = assign(assigns, :items, items)

    ~H"""
    <div class="space-y-2 text-sm leading-relaxed text-base-content/80">
      <div :for={item <- @items} class="prose prose-sm max-w-none">
        {markdown(item.text)}
      </div>
    </div>
    """
  end

  defp timeline_block(%{block: {:skill, items}} = assigns) do
    assigns = assign(assigns, :items, items)

    ~H"""
    <div class="flex flex-wrap gap-1.5">
      <span
        :for={skill <- @items}
        title={"Applied skill: #{skill[:path] || skill.name}"}
        class="inline-flex items-center gap-1.5 rounded-full border border-base-300 bg-violet-500/5 px-2.5 py-1 text-xs text-base-content/80"
      >
        <.icon name="hero-sparkles" class="size-3.5 text-violet-500" /> Skill:
        <span class="font-medium">{skill.name}</span>
      </span>
    </div>
    """
  end

  defp timeline_block(%{block: {:chart, items}} = assigns) do
    assigns = assign(assigns, :items, items)

    ~H"""
    <div class="space-y-3">
      <div
        :for={{chart, ci} <- Enum.with_index(@items)}
        id={"dra-chart-#{@turn_id}-#{@index}-#{ci}"}
        phx-hook="LightweightChart"
        phx-update="ignore"
        data-chart={
          Jason.encode!(%{
            slug: chart[:slug],
            range: chart[:range],
            summary: chart[:summary],
            series: chart.series
          })
        }
        class="overflow-hidden rounded-xl border border-base-300 bg-base-100"
      >
        <div class="flex items-center gap-2 border-b border-base-300 px-3.5 py-2 text-xs font-medium text-base-content/60">
          <.icon name="hero-chart-bar" class="size-4 text-primary" />
          <span class="text-base-content/80">{chart_caption(chart)}</span>
        </div>
        <div class="dra-chart-canvas w-full" style="height: 18rem;"></div>
      </div>
    </div>
    """
  end

  defp timeline_block(%{block: {:findings, items}} = assigns) do
    assigns = assign(assigns, :items, items)

    ~H"""
    <div class="space-y-2">
      <details
        :for={{f, fi} <- Enum.with_index(@items)}
        id={"dra-findings-#{@turn_id}-#{@index}-#{fi}"}
        phx-hook="KeepDetailsOpen"
        class="group rounded-lg border border-base-300 bg-indigo-500/5"
      >
        <summary class="flex cursor-pointer list-none items-center gap-2 px-3 py-2 text-sm text-base-content/80 hover:text-base-content">
          <.icon name="hero-clipboard-document-list" class="size-4 shrink-0 text-indigo-500" />
          <span class="font-medium">Sub-agent findings</span>
          <span :if={f[:unit]} class="truncate text-xs text-base-content/50">· {f[:unit]}</span>
          <span class="ml-auto shrink-0 text-xs text-base-content/50">
            {length(f.findings)} {pluralize(length(f.findings), "finding", "findings")}
          </span>
          <.icon
            name="hero-chevron-down"
            class="size-4 shrink-0 text-base-content/40 transition-transform group-open:rotate-0 -rotate-90"
          />
        </summary>
        <div class="space-y-2 border-t border-base-300 px-3 py-2.5">
          <p :if={f[:summary]} class="text-sm text-base-content/80">{f[:summary]}</p>
          <div :if={f.findings != []} class="overflow-x-auto">
            <table class="w-full text-xs">
              <thead>
                <tr class="text-left text-base-content/50">
                  <th class="py-1 pr-3 font-medium">Finding</th>
                  <th class="py-1 pr-3 font-medium">Evidence</th>
                  <th class="py-1 font-medium">Source</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- f.findings} class="border-t border-base-200 align-top">
                  <td class="py-1 pr-3">{finding_field(row, ~w(finding observation claim))}</td>
                  <td class="py-1 pr-3 text-base-content/70">
                    {finding_field(row, ~w(evidence data value))}
                  </td>
                  <td class="py-1 text-base-content/60">{finding_field(row, ~w(source))}</td>
                </tr>
              </tbody>
            </table>
          </div>
          <p :if={f.gaps != []} class="text-xs text-warning">Gaps: {Enum.join(f.gaps, "; ")}</p>
        </div>
      </details>
    </div>
    """
  end

  defp timeline_block(%{block: {:tools, items, running}} = assigns) do
    assigns =
      assign(assigns,
        items: items,
        running: running,
        status: group_status(items),
        summary: tool_summary(items)
      )

    ~H"""
    <details class="group rounded-xl border border-base-300 bg-base-200/30" open={@running}>
      <summary class="flex cursor-pointer list-none items-center gap-2 rounded-xl px-3.5 py-2.5 text-xs font-medium text-base-content/60 hover:text-base-content">
        <span :if={@running} class="loading loading-spinner loading-xs text-primary"></span>
        <.icon :if={@status == :ok} name="hero-check-circle" class="size-4 text-success" />
        <span :if={@status == :interrupted} title="Interrupted — some calls did not return">
          <.icon name="hero-minus-circle" class="size-4 text-base-content/40" />
        </span>
        <span class="text-base-content/80">Research</span>
        <span class="text-base-content/50">· {@summary}</span>
        <.icon
          name="hero-chevron-down"
          class="ml-auto size-4 text-base-content/40 transition-transform group-open:rotate-0 -rotate-90"
        />
      </summary>
      <div class="space-y-3 border-t border-base-300 px-3.5 py-3">
        <%= for {item, i} <- Enum.with_index(Timeline.coalesce(@items)) do %>
          <.tool_item item={item} index={i} dom_id={"dra-tools-#{@turn_id}-#{@index}-#{i}"} />
        <% end %>
      </div>
    </details>
    """
  end

  attr :item, :any, required: true
  attr :index, :integer, required: true
  attr :dom_id, :string, default: nil

  defp tool_item(%{item: {:mcp_group, items}} = assigns) do
    assigns = assign(assigns, items: items, status: group_status(items))

    ~H"""
    <details id={@dom_id} phx-hook="KeepDetailsOpen" class="group">
      <summary class="flex cursor-pointer list-none items-center gap-2 text-sm text-base-content/80 hover:text-base-content">
        <.icon name="hero-circle-stack" class="size-4 text-indigo-500" />
        <span class="font-medium">Data tools</span>
        <span class="text-xs text-base-content/60">
          · {length(@items)} {pluralize(length(@items), "call", "calls")}
        </span>
        <span :if={@status == :running} class="loading loading-spinner loading-xs ml-auto"></span>
        <.icon :if={@status == :ok} name="hero-check-circle" class="ml-auto size-3.5 text-success" />
        <span
          :if={@status == :interrupted}
          class="ml-auto"
          title="Interrupted — some calls did not return"
        >
          <.icon name="hero-minus-circle" class="size-3.5 text-base-content/40" />
        </span>
        <.icon
          name="hero-chevron-down"
          class="size-4 transition-transform group-open:rotate-0 -rotate-90"
        />
      </summary>
      <div class="ml-6 mt-1.5 space-y-1.5">
        <.mcp_call_row :for={call <- @items} call={call} />
      </div>
    </details>
    """
  end

  defp tool_item(%{item: %{kind: :search}} = assigns) do
    ~H"""
    <div class="space-y-1.5">
      <div class="flex items-center gap-2 text-sm text-base-content/80">
        <.icon name="hero-globe-alt" class="size-4 shrink-0 text-base-content/60" />
        <span class="truncate">{@item.query}</span>
        <span :if={Map.get(@item, :count)} class="ml-auto shrink-0 text-xs text-base-content/60">
          {@item.count} results
        </span>
        <span :if={is_nil(Map.get(@item, :count))} class="loading loading-spinner loading-xs ml-auto"></span>
      </div>
      <div
        :if={Map.get(@item, :results) not in [nil, []]}
        class="ml-6 grid grid-cols-1 gap-x-4 gap-y-1 sm:grid-cols-2"
      >
        <.search_result :for={result <- Enum.take(@item.results, 8)} result={result} />
      </div>
    </div>
    """
  end

  defp tool_item(%{item: %{kind: :status}} = assigns) do
    ~H"""
    <p class={[
      "text-xs",
      if(@item.state == "mcp_error", do: "text-error", else: "text-base-content/60")
    ]}>
      {if @item.state == "mcp_error",
        do: "MCP error: #{@item[:detail] || "connection failed"}",
        else: "Connected to data tools"}
    </p>
    """
  end

  defp tool_item(assigns), do: ~H""

  attr :result, :map, required: true

  # One search hit. A result whose URL is not http(s) still shows its title, just
  # not as a link — the label markup is shared so the two branches cannot drift.
  defp search_result(assigns) do
    assigns = assign(assigns, :href, safe_http_url(assigns.result.url))

    ~H"""
    <.link
      :if={@href}
      href={@href}
      target="_blank"
      rel="noopener noreferrer"
      title={"#{@result.title} — #{@href}"}
      class="flex items-center gap-1.5 overflow-hidden text-xs text-base-content/60 hover:text-base-content"
    >
      <.search_result_label result={@result} />
    </.link>
    <span
      :if={!@href}
      title={@result.title}
      class="flex items-center gap-1.5 overflow-hidden text-xs text-base-content/60"
    >
      <.search_result_label result={@result} />
    </span>
    """
  end

  attr :result, :map, required: true

  defp search_result_label(assigns) do
    ~H"""
    <.favicon domain={@result.domain} />
    <span class="shrink-0 text-base-content/40">{@result.domain}</span>
    <span class="truncate">{@result.title}</span>
    """
  end

  attr :domain, :string, default: nil

  # Favicons are fetched from Google's public favicon service, so the browser
  # discloses each researched domain to Google. Accepted deliberately: it is an
  # internal admin tool and the alternative is fetching (and caching) icons from
  # arbitrary researched hosts ourselves. Swap the src to change that.
  defp favicon(assigns) do
    ~H"""
    <img
      :if={@domain not in [nil, ""]}
      src={"https://www.google.com/s2/favicons?domain=#{@domain}&sz=32"}
      alt=""
      class="size-3.5 shrink-0 rounded-sm"
    />
    <.icon
      :if={@domain in [nil, ""]}
      name="hero-globe-alt"
      class="size-3.5 shrink-0 text-base-content/60"
    />
    """
  end

  attr :call, :map, required: true

  defp mcp_call_row(assigns) do
    assigns =
      assign(assigns,
        args: arg_summary(assigns.call),
        status: call_status(assigns.call),
        has_output: !!assigns.call[:summary]
      )

    ~H"""
    <details class="text-xs">
      <summary class="flex cursor-pointer list-none items-center gap-2 text-left">
        <span class="truncate font-mono text-base-content/80">
          {@call.tool}{if @args != "", do: "(#{@args})", else: "()"}
        </span>
        <span :if={@status == :running} class="loading loading-spinner loading-xs ml-auto"></span>
        <.icon
          :if={@status == :ok}
          name="hero-check-circle"
          class="ml-auto size-3 text-success"
        />
        <.icon :if={@status == :error} name="hero-x-circle" class="ml-auto size-3 text-error" />
        <span :if={@status == :interrupted} class="ml-auto" title="Interrupted — did not return">
          <.icon name="hero-minus-circle" class="size-3 text-base-content/40" />
        </span>
      </summary>
      <pre
        :if={@has_output}
        class="mt-1 max-h-32 overflow-auto whitespace-pre-wrap rounded bg-base-300/40 p-2 text-[11px] text-base-content/60"
      >{@call.summary}</pre>
    </details>
    """
  end

  # Status of a whole group of tool items (the "Research" block, the "Data tools"
  # fold): :running while anything is in flight, :interrupted when the group holds
  # a call that never returned, else :ok. Individual failures stay on their own
  # row — a research run routinely tolerates a failed call, so one must not paint
  # the whole group red; a group that was cut short must not claim success either.
  defp group_status(items) do
    cond do
      Timeline.tools_running?(items) -> :running
      Enum.any?(items, &(&1.kind == :mcp and is_nil(Map.get(&1, :ok)))) -> :interrupted
      true -> :ok
    end
  end

  # One of :running | :ok | :error | :interrupted. `ok: nil` on a finished call
  # means the run ended before the result arrived — neither success nor failure.
  defp call_status(call) do
    cond do
      Map.get(call, :done) != true -> :running
      call[:ok] == true -> :ok
      call[:ok] == false -> :error
      true -> :interrupted
    end
  end

  attr :id, :integer, required: true
  attr :report, :string, required: true

  defp report_card(assigns) do
    ~H"""
    <div class="overflow-hidden rounded-xl border border-base-300 bg-base-100 shadow-sm">
      <div class="flex items-center gap-2 border-b border-base-300 bg-base-200/40 px-4 py-2.5">
        <.icon name="hero-document-text" class="size-4 text-primary" />
        <span class="text-xs font-semibold uppercase tracking-wide text-base-content/60">
          Research report
        </span>
        <button
          type="button"
          id={"copy-report-#{@id}"}
          phx-hook="Copy"
          data-copy={@report}
          class="ml-auto inline-flex items-center gap-1.5 rounded-lg px-2 py-1 text-xs text-base-content/50 transition hover:bg-base-200 hover:text-base-content"
        >
          <.icon name="hero-clipboard-document" class="size-4 [.copied_&]:hidden" />
          <.icon name="hero-check" class="hidden size-4 text-success [.copied_&]:inline-block" />
          <span class="[.copied_&]:hidden">Copy</span>
          <span class="hidden [.copied_&]:inline">Copied</span>
        </button>
      </div>
      <div class="space-y-4 px-5 py-4">
        <%= for seg <- ReportMarkdown.split_charts(ReportMarkdown.reflow_sources(@report)) do %>
          <%= case seg do %>
            <% {:md, text} -> %>
              <div class="prose prose-sm max-w-none">{markdown(text)}</div>
            <% {:chart, spec} -> %>
              {ChartRenderer.render(spec)}
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  # -- view helpers ------------------------------------------------------------

  # Mark an in-flight tool item as settled (done, outcome unknown) so a terminal
  # turn shows no spinner. ok stays nil → the row renders a neutral "interrupted"
  # icon, not a misleading success check or error cross.
  defp settle_item(%{kind: :mcp, done: true} = item), do: item
  defp settle_item(%{kind: :mcp} = item), do: Map.put(item, :done, true)

  defp settle_item(%{kind: :search} = item) do
    if is_nil(Map.get(item, :count)),
      do: Map.put(item, :count, length(item[:results] || [])),
      else: item
  end

  defp settle_item(item), do: item

  # Schema-tolerant read of a finding row: cheap models drift the keys
  # (finding/observation, evidence/data), so try each in order.
  defp finding_field(row, keys) when is_map(row) do
    Enum.find_value(keys, "", fn k ->
      case row[k] do
        v when is_binary(v) and v != "" -> v
        _ -> nil
      end
    end)
  end

  defp finding_field(_, _), do: ""

  # A compact caption from a (timeline) chart's slug/range plus its series labels.
  # Series here come straight off the wire, so the keys are strings — see the
  # "Not the only chart path" note in `SanbaseWeb.DeepResearch.ChartRenderer`.
  defp chart_caption(chart) do
    base = [chart[:slug], chart[:range]] |> Enum.reject(&is_nil/1) |> Enum.join(" · ")

    labels =
      (chart.series || [])
      |> Enum.map(&(&1["label"] || &1["name"]))
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.uniq()

    case {base, labels} do
      {"", []} -> "Chart"
      {b, []} -> b
      {"", ls} -> Enum.join(ls, " vs ")
      {b, ls} -> "#{b} — #{Enum.join(ls, " vs ")}"
    end
  end

  # Drop narration that duplicates the report or clarification card — those are
  # rendered separately, so showing the same text in the feed is just noise.
  defp visible_items(timeline, report, clarification) do
    Enum.reject(timeline, fn item ->
      item.kind == :thinking and
        ((is_binary(report) and String.trim(item.text) == String.trim(report)) or
           (is_list(clarification) and clarification != [] and
              Enum.all?(clarification, &String.contains?(item.text, &1))))
    end)
  end

  defp tool_summary(items) do
    n_search = Enum.count(items, &(&1.kind == :search))
    n_mcp = Enum.count(items, &(&1.kind == :mcp))

    parts =
      []
      |> append_if(n_search > 0, "#{n_search} web #{pluralize(n_search, "search", "searches")}")
      |> append_if(n_mcp > 0, "#{n_mcp} data #{pluralize(n_mcp, "call", "calls")}")

    case parts do
      [] -> "reasoning"
      parts -> Enum.join(parts, " · ")
    end
  end

  defp append_if(list, true, value), do: list ++ [value]
  defp append_if(list, false, _value), do: list

  defp pluralize(1, singular, _plural), do: singular
  defp pluralize(_n, _singular, plural), do: plural

  defp arg_summary(%{args: args}) when is_map(args) do
    args
    |> Enum.reject(fn {_k, v} -> v in [nil, "None", ""] end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}=#{stringify(v)}" end)
    |> String.slice(0, 140)
  end

  defp arg_summary(_), do: ""

  defp stringify(v) when is_binary(v), do: v
  defp stringify(v), do: inspect(v)

  defp safe_http_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme} when scheme in ["http", "https"] -> url
      _ -> nil
    end
  end

  defp safe_http_url(_), do: nil

  # A finished turn carries its own `finished_at`, so it needs no wall clock and
  # is rendered with `now_ms: nil` — that keeps its assigns stable across ticks.
  defp elapsed_seconds(turn, now_ms) do
    end_ms = turn.finished_at || now_ms || turn.started_at
    max(0, div(end_ms - turn.started_at, 1000))
  end

  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"

  defp format_duration(seconds) do
    minutes = div(seconds, 60)
    rest = rem(seconds, 60)
    "#{minutes}m #{String.pad_leading(Integer.to_string(rest), 2, "0")}s"
  end

  # The report/thinking markdown comes from the research agent over the wire, so
  # sanitize the rendered HTML (Earmark is a converter, not a sanitizer) before
  # injecting it raw — strips scripts and `javascript:` links, keeps the tags a
  # report needs (headings, links, tables, code, lists).
  defp markdown(text) when is_binary(text) do
    text
    |> Earmark.as_html!()
    |> HtmlSanitizeEx.markdown_html()
    |> Phoenix.HTML.raw()
  end

  defp markdown(_), do: ""

  defp phase_label(:planning), do: "Planning research"
  defp phase_label(:researching), do: "Researching"
  defp phase_label(:writing), do: "Writing report"
  defp phase_label(_), do: "Working"
end
