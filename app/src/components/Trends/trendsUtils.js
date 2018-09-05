import { push } from 'react-router-redux'

export const parseTrendsGQLProps = ({
  data: { topicSearch = { chartsData: {} } }
}) => {
  const { __typename, ...sources } = topicSearch.chartsData
  return { sources }
}

export const mergeDataSourcesForChart = sources =>
  Object.keys(sources).reduce((acc, source) => {
    if (!sources[source]) return acc

    for (const { datetime, mentionsCount } of sources[source]) {
      acc.set(datetime, mentionsCount + (acc.get(datetime) || 0))
    }
    return acc
  }, new Map())

export const gotoExplore = dispatch => ({
  gotoExplore: topic => dispatch(push(`/trends/explore/${topic}`))
})

export const Source = {
  telegram: 'Telegram',
  reddit: 'Reddit',
  professionalTradersChat: 'Professional Traders Chat',
  merged: 'Merged sources'
}

const defaultValidSources = ['merged']

export const validateSearchSources = (sources = defaultValidSources) => {
  if (sources.includes('merged')) {
    return defaultValidSources
  }

  const validSources = sources.filter(source => Source.hasOwnProperty(source))

  return validSources.length !== 0 ? validSources : defaultValidSources
}
