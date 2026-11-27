<script lang="ts">
  type TProps = {
    class?: string;
    change: number;
  };

  const { class: className = "", change }: TProps = $props();

  const colorClass =
    change === 0 ? "text-orange" : change < 0 ? "text-red" : "text-lima";
  const title =
    change === 0 ? "Not changed" : change > 0 ? "Increased" : "Decreased";
</script>

<span class="{colorClass} {className}" {title}>
  {change >= 0 ? "+" : ""}{change}%
</span>
