import type { TrendingStoriesData } from './contract'

const HOUR_MS = 60 * 60 * 1000

export const MOCK_DATA: TrendingStoriesData = {
  time_period: '1h',
  size: 3,
  period_start: new Date(Date.now() - HOUR_MS).toISOString(),
  period_end: new Date().toISOString(),
  total_time_periods: 1,
  trending_stories: [
    {
      datetime: new Date().toISOString(),
      top_stories: [
        {
          title: 'Bitcoin ETF inflows hit record $1.2B in a single day',
          summary:
            'Institutional demand surges as spot Bitcoin ETFs see unprecedented capital inflows, signaling renewed bullish sentiment from traditional finance.',
          bearish_sentiment_ratio: 0.12,
          bullish_sentiment_ratio: 0.88,
          score: 97.4,
          query: 'bitcoin etf inflows record',
          related_tokens: ['BTC_bitcoin', 'ETH_ethereum'],
        },
        {
          title: 'Ethereum L2s surpass mainnet in daily transaction volume',
          summary:
            'Layer 2 scaling solutions collectively process more transactions than Ethereum mainnet for the first time.',
          bearish_sentiment_ratio: 0.18,
          bullish_sentiment_ratio: 0.72,
          score: 84.1,
          query: 'ethereum layer2 transactions mainnet',
          related_tokens: ['ETH_ethereum', 'ARB_arbitrum', 'OP_optimism'],
        },
        {
          title: 'Solana network congestion sparks debate over validator incentives',
          summary:
            'A wave of meme coin launches caused network slowdowns, reigniting discussions about Solana fee market.',
          bearish_sentiment_ratio: 0.61,
          bullish_sentiment_ratio: 0.31,
          score: 76.8,
          query: 'solana network congestion validators',
          related_tokens: ['SOL_solana'],
        },
      ],
    },
  ],
}
