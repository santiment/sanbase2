<script lang="ts">
  import { sluggify } from "san-webkit-next/utils/url";
  import StoryCard from "./StoryCard.svelte";
  import WidgetShell from "../../lib/WidgetShell.svelte";
  import { useMcpApp } from "../../lib/useMcpApp.svelte";
  import { parseTrendingStories, type Story } from "./contract";

  const SANTIMENT_TRENDS_BASE = "https://app.santiment.net/labs/trends/explore";
  const SANTIMENT_SOCIAL_TRENDS = "https://app.santiment.net/social-trends";

  const { mcpApp } = useMcpApp({
    name: "santiment-social-trends",
    parse: parseTrendingStories,
  });

  const stories = $derived<Story[]>(
    mcpApp.$.data?.trending_stories?.at(-1)?.top_stories ?? [],
  );

  function openStoryOnSantiment(story: Story) {
    const slug = sluggify(story.query || story.title);
    if (slug) mcpApp.openLink(`${SANTIMENT_TRENDS_BASE}/${slug}`);
  }
</script>

{#key mcpApp.isNightMode$}
  <WidgetShell
    title="📈 Social Trends"
    badge={mcpApp.$.data?.time_period}
    isNightMode={mcpApp.isNightMode$}
    loading={mcpApp.$.loading}
    error={mcpApp.$.error}
    empty={stories.length === 0}
    emptyMessage="No trending stories found."
  >
    {#snippet loadingSkeleton()}
      <ul class="flex flex-col gap-2.5 list-none">
        {#each Array(3) as _}
          <li
            class="border border-porcelain rounded-lg px-3.5 py-3 flex flex-col gap-2"
          >
            <div class="skeleton h-4 w-3/4"></div>
            <div class="flex gap-3 mt-1.5">
              <div class="skeleton h-3 w-16"></div>
              <div class="skeleton h-3 w-16"></div>
              <div class="skeleton h-3 w-20"></div>
            </div>
          </li>
        {/each}
      </ul>
      <div class="mt-4 flex justify-end">
        <div class="skeleton h-3 w-40"></div>
      </div>
    {/snippet}

    <ul class="flex flex-col gap-2.5 list-none">
      {#each stories as story}
        <li>
          <StoryCard {story} onclick={() => openStoryOnSantiment(story)} />
        </li>
      {/each}
    </ul>

    {#snippet footer()}
      <div class="mt-4 flex justify-end">
        <button
          type="button"
          onclick={() => mcpApp.openLink(SANTIMENT_SOCIAL_TRENDS)}
          class="text-xs font-medium text-green hover:underline focus-visible:outline-2 focus-visible:outline-green focus-visible:outline-offset-2 rounded"
        >
          See more social trends on Santiment →
        </button>
      </div>
    {/snippet}
  </WidgetShell>
{/key}
