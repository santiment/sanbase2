import { push } from 'react-router-redux'

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
  merged: 'Merged Sources'
}

export const SourceColor = {
  telegram: 'rgb(0, 0, 255)',
  reddit: 'rgb(255, 0, 0)',
  professionalTradersChat: 'rgb(20, 200, 20)',
  merged: 'rgb(255, 193, 7)'
}

const defaultSources = ['merged']

export const validateSearchSources = (sources = defaultSources) => {
  if (!(sources instanceof Array)) return defaultSources
  if (sources.includes('merged')) {
    return defaultSources
  }

  const validSources = sources.filter(source => Source.hasOwnProperty(source))

  return validSources.length !== 0 ? validSources : defaultSources
}

export const parseExampleSettings = ({ interval, sources }) => {
  let text = 'For '

  switch (interval) {
    case '6m':
      text += '6 months'
      break
    case '1w':
      text += '7 days'
      break
    case '3m':
      text += '3 months'
      break

    default:
      text += '6 months'
      break
  }

  for (const source of sources) {
    text += `, ${Source[source]}`
  }

  text += ' mentions'
  return text
  // For 7 days, Merged sources
}
