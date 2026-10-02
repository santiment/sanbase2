/**
 * Contract for the Social Trends MCP App.
 *
 * This is the single source of truth for the shape of data exchanged between
 * the Elixir MCP server (Sanbase.MCP.TrendingStoriesTool) and this widget.
 *
 * Any change here MUST be mirrored in the server's tool implementation
 * (lib/sanbase/mcp/trending_stories_tool.ex) and ideally exposed via
 * `output_schema` so Claude can validate.
 */

import type { CallToolResult } from '@modelcontextprotocol/sdk/types.js'

export type Story = {
  title: string
  summary: string
  bullish_sentiment_ratio: number
  bearish_sentiment_ratio: number
  score: number
  query: string
  related_tokens: string[]
}

export type TimePeriod = {
  datetime: string
  top_stories: Story[]
}

export type TrendingStoriesData = {
  time_period: string
  size?: number
  period_start?: string
  period_end?: string
  total_time_periods: number
  trending_stories: TimePeriod[]
}

/** Narrow a tool result into `TrendingStoriesData`, or return `null`. */
export function parseTrendingStories(result: CallToolResult): TrendingStoriesData | null {
  const sc = result.structuredContent as Partial<TrendingStoriesData> | undefined
  if (!sc || typeof sc !== 'object') return null
  if (!Array.isArray(sc.trending_stories)) return null
  return sc as TrendingStoriesData
}
