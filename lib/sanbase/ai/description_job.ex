defmodule Sanbase.AI.DescriptionJob do
  @moduledoc """
  GenServer that manages bulk AI description generation.

  Holds a single global job state (one job at a time), so progress survives
  LiveView navigation. Any LiveView can subscribe to PubSub updates and
  reconnect to a running job when remounting.

  Also exposes generation helpers (build_user_message/2, run_generation/3,
  save_ai_description/3) as public functions so the LiveView can reuse them
  for single-item generation without duplication.
  """

  use GenServer

  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Insight.Post
  alias Sanbase.Chart.Configuration
  alias Sanbase.UserList
  alias Sanbase.AI.OpenAIClient

  @pubsub Sanbase.PubSub
  @topic "ai_description_job"

  @idle_state %{
    status: :idle,
    # :idle | :running | :done | :cancelled
    user_id: nil,
    entity_type: nil,
    total: 0,
    done: 0,
    failed: 0,
    errors: []
  }

  @system_prompt ~S"""
  You are a controlled semantic expansion engine for Santiment.

  Your task: convert short author inputs into compact, structured micro-descriptions optimized for:
  - Human readability and UI fit
  - Semantic search and embedding quality
  - AI agent interpretability

  ## PRIMARY OBJECTIVE

  Generate a description with two layers:
  1. **Lead sentence** — clean, unlabeled, human-readable. This is what the user reads first.
  2. **Structured block** — labeled fields for AI agents, search, and embeddings. Visually separated by a blank line.

  Both layers must end with classification tags, respect entity boundaries, and remain concise.

  ## ENTITY RULES

  ### You MUST NOT introduce:
  - New metrics or measurable variables
  - New datasets or analytical dimensions
  - Predictive claims not present in input
  - Price targets or causal guarantees

  ### You MAY:
  - Expand abbreviations (e.g., DAA → Daily Active Addresses)
  - Clarify terminology and definitions
  - Explain behavioral implications of the tracked entity
  - Add directional interpretation (↑/↓)
  - Reference commonly paired entities in the `Context` field only

  ## TYPE DETECTION

  Classify input as one of:
  - **Metric / Chart** — tracks a measurable value over time
  - **Screener** — filters assets by a condition
  - **Watchlist** — curates a group of assets by theme or logic

  ## OUTPUT FORMATS

  ### Format A — Metric / Chart
  ```
  [One clear sentence. What is tracked. ≤25 words. No label.]

  Measures: [Tracked entity/entities. Expand abbreviations.]
  Reflects: [Market behavior category]
  Interpretation: ↑ [Entity] → [Behavioral implication] · ↓ [Entity] → [Opposite]
  Context: [Commonly analyzed alongside X — optional]
  Tags: Category: [X] | Signal Type: [Y] | Market Scope: [Z]
  ```

  ### Format B — Screener
  ```
  [One clear sentence. What condition filters assets. ≤25 words. No label.]

  Condition: [Exact filtering logic from input.]
  Detects: [Market situation: accumulation, breakout potential, overvaluation, etc.]
  Behavior: [What assets meeting this condition historically exhibit.]
  Tags: Category: Screener | Signal Type: [Y] | Market Scope: [Z]
  ```

  ### Format C — Watchlist
  ```
  [One clear sentence. What group of assets and why. ≤25 words. No label.]

  Selection Logic: [Theme, sector, or on-chain behavior used for curation.]
  Common Trait: [Shared characteristic of listed assets.]
  Use Case: [What to monitor: rotation, narrative shifts, capital flows, etc.]
  Tags: Category: Watchlist | Signal Type: [Y] | Market Scope: [Z]
  ```

  ## FIELD RULES
  - Lead sentence: exactly one sentence, no label prefix, ≤25 words, followed by blank line.
  - Tags (mandatory): Category | Signal Type | Market Scope

  **Category**: On-chain Metric | Social Metric | Derivatives Metric | Market Metric | Network Metric | Screener | Watchlist
  **Signal Type**: Sentiment | Leverage | Accumulation | Distribution | Liquidity | Volatility | Network Activity | Capital Flow | Valuation | Development
  **Market Scope**: Spot | Futures | DeFi | Cross-market | Network-level | Social

  ## MARKET BEHAVIOR VOCABULARY
  capital inflow/outflow · leverage demand/deleveraging · market stress/euphoria ·
  liquidity conditions · accumulation/distribution · network growth/declining activity ·
  holder conviction/capitulation · crowded positioning · smart money movement · narrative rotation

  Avoid: "useful," "important," "interesting," "notable," "key," "significant."

  **Validate before output: no new entities, correct format, ≤25 word lead sentence, tags present.**
  """

  # ─── Client API ────────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Subscribe to PubSub job updates. Caller receives `{:job_update, state}` messages."
  def subscribe, do: Phoenix.PubSub.subscribe(@pubsub, @topic)

  @doc "Returns current job state. Safe to call when GenServer is not started."
  def get_state do
    case Process.whereis(__MODULE__) do
      nil -> @idle_state
      _pid -> GenServer.call(__MODULE__, :get_state)
    end
  end

  @doc "Start a new bulk job. Returns `:ok` or `{:error, :already_running}`."
  def start_job(user_id, entity_type, entities, custom_prompt) do
    GenServer.call(__MODULE__, {:start_job, user_id, entity_type, entities, custom_prompt})
  end

  @doc "Cancel the running job. In-flight OpenAI call for the current item still completes."
  def cancel, do: GenServer.cast(__MODULE__, :cancel)

  # ─── Public helpers (reused by LiveView for single-item generation) ─────────

  @doc "Build the user message sent to the LLM for a given entity."
  def build_user_message(entity, entity_type), do: do_build_user_message(entity, entity_type)

  @doc "Run generation for a single entity. Returns `{:ok, text}` or `{:error, reason}`."
  def run_generation(entity, entity_type, custom_prompt \\ "") do
    user_message = do_build_user_message(entity, entity_type)

    system_prompt =
      if custom_prompt && custom_prompt != "" do
        @system_prompt <>
          "\n\n## REFINEMENT PASS\n\n" <>
          "After producing the description per the rules above, rewrite it by applying " <>
          "the following adjustment. Return only the final adjusted description — do not " <>
          "show intermediate steps.\n\n" <>
          custom_prompt
      else
        @system_prompt
      end

    OpenAIClient.chat_completion(system_prompt, user_message, max_tokens: 400, temperature: 0.4)
  end

  @doc "Persist `ai_description` for a single entity."
  def save_ai_description(:insights, id, text) do
    Repo.update_all(from(p in Post, where: p.id == ^id), set: [ai_description: text])
  end

  def save_ai_description(:charts, id, text) do
    Repo.update_all(from(c in Configuration, where: c.id == ^id), set: [ai_description: text])
  end

  def save_ai_description(type, id, text) when type in [:screeners, :watchlists] do
    Repo.update_all(from(ul in UserList, where: ul.id == ^id), set: [ai_description: text])
  end

  # ─── GenServer callbacks ───────────────────────────────────────────────────

  @impl true
  def init(_opts), do: {:ok, @idle_state}

  @impl true
  def handle_call(:get_state, _from, state), do: {:reply, state, state}

  @impl true
  def handle_call(:running?, _from, state), do: {:reply, state.status == :running, state}

  @impl true
  def handle_call({:start_job, _, _, _, _}, _from, %{status: :running} = state) do
    {:reply, {:error, :already_running}, state}
  end

  @impl true
  def handle_call({:start_job, user_id, entity_type, entities, custom_prompt}, _from, _prev) do
    new_state = %{
      status: :running,
      user_id: user_id,
      entity_type: entity_type,
      total: length(entities),
      done: 0,
      failed: 0,
      errors: []
    }

    gen_pid = self()

    Task.Supervisor.start_child(Sanbase.TaskSupervisor, fn ->
      Enum.each(entities, fn {entity, type} ->
        # Check cancellation before each item (one API call can still run after cancel)
        if GenServer.call(gen_pid, :running?) do
          result =
            try do
              run_generation(entity, type, custom_prompt)
            rescue
              e -> {:error, Exception.message(e)}
            catch
              kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
            end

          send(gen_pid, {:item_done, result, entity.id, type})
        end
      end)

      send(gen_pid, :job_finished)
    end)

    broadcast(new_state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast(:cancel, state) do
    new_state = %{state | status: :cancelled}
    broadcast(new_state)
    {:noreply, new_state}
  end

  # Ignore item results after cancellation / completion
  @impl true
  def handle_info({:item_done, _, _, _}, %{status: s} = state) when s != :running do
    {:noreply, state}
  end

  @impl true
  def handle_info({:item_done, {:ok, text}, id, type}, state) do
    save_ai_description(type, id, text)
    new_state = %{state | done: state.done + 1}
    broadcast(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:item_done, {:error, reason}, id, _type}, state) do
    new_state = %{
      state
      | failed: state.failed + 1,
        errors: [{id, inspect(reason)} | state.errors]
    }

    broadcast(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:job_finished, %{status: :running} = state) do
    new_state = %{state | status: :done}
    broadcast(new_state)
    {:noreply, new_state}
  end

  # :job_finished after cancel → ignore, already broadcast :cancelled
  @impl true
  def handle_info(:job_finished, state), do: {:noreply, state}

  # Ignore Task supervisor ref/down messages
  @impl true
  def handle_info({ref, _}, state) when is_reference(ref), do: {:noreply, state}

  @impl true
  def handle_info({:DOWN, _, :process, _, _}, state), do: {:noreply, state}

  # ─── Private ──────────────────────────────────────────────────────────────

  defp broadcast(state) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:job_update, state})
  end

  defp do_build_user_message(%Post{} = post, :insights) do
    """
    Type: Insight
    Title: #{post.title}
    Short description: #{post.short_desc || "(none)"}
    """
    |> String.trim()
  end

  defp do_build_user_message(%Configuration{} = config, :charts) do
    metrics = Enum.join(config.metrics || [], ", ")

    """
    Type: Chart
    Title: #{config.title || "(untitled)"}
    Current description: #{config.description || "(none)"}
    Metrics tracked: #{if metrics != "", do: metrics, else: "(none)"}
    """
    |> String.trim()
  end

  defp do_build_user_message(%UserList{} = ul, :screeners) do
    """
    Type: Screener
    Name: #{ul.name}
    Current description: #{ul.description || "(none)"}
    Filter function: #{inspect(ul.function)}
    """
    |> String.trim()
  end

  defp do_build_user_message(%UserList{} = ul, :watchlists) do
    """
    Type: Watchlist
    Name: #{ul.name}
    Current description: #{ul.description || "(none)"}
    """
    |> String.trim()
  end
end
