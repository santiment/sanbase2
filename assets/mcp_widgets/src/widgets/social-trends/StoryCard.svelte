<script lang="ts">
  import { tv } from 'tailwind-variants'
  import type { Story } from './contract'

  const {
    story,
    onclick,
  }: {
    story: Story
    onclick: () => void
  } = $props()

  const bull = $derived(Math.round((story.bullish_sentiment_ratio ?? 0) * 100))
  const bear = $derived(Math.round((story.bearish_sentiment_ratio ?? 0) * 100))

  const card = tv({
    base: 'w-full text-left border border-porcelain rounded-lg px-3.5 py-3 transition-colors hover:border-green focus-visible:border-green focus-visible:outline-2 focus-visible:outline-green focus-visible:outline-offset-1',
  })
</script>

<article>
  <button class={card()} {onclick}>
    <header>
      <p class="text-sm font-medium text-rhino leading-snug">{story.title}</p>
    </header>
    <footer class="flex gap-3 mt-1.5">
      <span class="text-xs font-medium text-lima">▲ {bull}% bull</span>
      <span class="text-xs font-medium text-red">▼ {bear}% bear</span>
      <span class="text-xs text-waterloo">score: {story.score.toFixed(1)}</span>
    </footer>
  </button>
</article>
