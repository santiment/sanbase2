import moment from 'moment'
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
  professional_traders_chat: 'Traders Forums',
  merged: 'Merged Sources'
}

export const SourceColor = {
  telegram: 'rgb(0, 0, 255)',
  reddit: 'rgb(255, 0, 0)',
  professionalTradersChat: 'rgb(20, 200, 20)',
  merged: 'rgb(255, 193, 7)'
}

export const sourcesMeta = {
  merged: {
    index: 'merged',
    name: 'Total Mentions',
    color: '#AC74D9',
    value: 0
  },
  telegram: {
    index: 'telegram',
    name: 'Telegram',
    color: '#55ABF8',
    value: 0
  },
  reddit: {
    index: 'reddit',
    name: 'Reddit',
    color: '#F17682',
    value: 0
  },
  professional_traders_chat: {
    index: 'professional_traders_chat',
    name: 'Professional Traders Chat',
    color: '#44C7A5',
    value: 0
  }
}

const getMergedMentionsDataset = mentionsBySources =>
  Object.keys(mentionsBySources).reduce((acc, source) => {
    for (const { datetime, mentionsCount } of mentionsBySources[source]) {
      if (acc[datetime] !== undefined) {
        acc[datetime].merged += mentionsCount
      } else {
        acc[datetime] = {
          datetime,
          merged: mentionsCount
        }
      }
    }
    return acc
  }, {})

const getComposedMentionsDataset = (mentionsBySources, selectedSources) => {
  return selectedSources.reduce((acc, source) => {
    for (const { datetime, mentionsCount } of mentionsBySources[source]) {
      if (acc[datetime] !== undefined) {
        acc[datetime][source] = mentionsCount
      } else {
        acc[datetime] = {
          datetime,
          [source]: mentionsCount
        }
      }
    }
    return acc
  }, {})
}

export const getMentionsChartData = (mentionsBySources, selectedSources) =>
  Object.values(
    selectedSources.includes('merged')
      ? getMergedMentionsDataset(mentionsBySources)
      : getComposedMentionsDataset(mentionsBySources, selectedSources)
  ).sort((a, b) => (moment(a.datetime).isAfter(b.datetime) ? 1 : -1))

const defaultSources = ['merged']

export const validateSearchSources = (sources = defaultSources) => {
  if (!(sources instanceof Array)) return defaultSources
  if (sources.includes('merged')) {
    return defaultSources
  }

  const validSources = sources.filter(source => Source.hasOwnProperty(source))

  return validSources.length !== 0 ? validSources : defaultSources
}

const getTimeRangeText = timeRange => {
  let text = 'last '

  switch (timeRange) {
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

  return text
}
const getSourcesText = sources => {
  const text = 'mentions'

  if (sources.includes('merged')) {
    return `Total ${text}`
  }
}

export const parseExampleSettings = ({ timeRange, sources }) => {
  let text = getSourcesText(sources)
  return text + ', ' + getTimeRangeText(timeRange)
}
