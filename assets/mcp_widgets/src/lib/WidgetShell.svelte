<script lang="ts">
  import type { Snippet } from "svelte";

  type TProps = {
    title: string;
    badge?: string | null;
    loading: boolean;
    error?: string | null;
    empty?: boolean;
    emptyMessage?: string;
    loadingSkeleton?: Snippet;
    summary?: Snippet;
    children: Snippet;
    footer?: Snippet;
  };

  let {
    title,
    badge = null,
    loading,
    error = null,
    empty = false,
    emptyMessage = "No data available.",
    loadingSkeleton,
    summary,
    children,
    footer,
  }: TProps = $props();
</script>

<section class="bg-white text-rhino p-4" aria-label={title}>
  <header class="flex items-center gap-3 mb-3">
    {#if loading}
      <div class="skeleton h-5 w-40"></div>
      <div class="skeleton h-4 w-12"></div>
    {:else}
      <h2 class="text-base font-semibold text-rhino">{title}</h2>
      {#if badge}
        <span
          class="text-xs font-medium bg-green px-2 py-0.5 rounded text-white-day"
        >
          {badge}
        </span>
      {/if}
    {/if}
  </header>

  <div aria-live="polite" aria-atomic="true">
    {#if error}
      <p class="text-center py-8 text-sm text-red" role="alert">{error}</p>
    {:else if loading}
      {#if loadingSkeleton}
        <div aria-label="Loading">{@render loadingSkeleton()}</div>
      {:else}
        <div class="flex justify-center py-10" aria-label="Loading">
          <div class="loading-spin" style:--loading-size="28px"></div>
        </div>
      {/if}
    {:else if empty}
      <p class="text-center py-8 text-sm text-waterloo">{emptyMessage}</p>
    {:else}
      {#if summary}
        {@render summary()}
      {/if}

      {@render children()}

      {#if footer}
        {@render footer()}
      {/if}
    {/if}
  </div>
</section>
