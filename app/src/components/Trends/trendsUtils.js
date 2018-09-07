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

export const SourceColor = {
  telegram: 'rgb(0, 0, 255)',
  reddit: 'rgb(255, 0, 0)',
  professionalTradersChat: 'rgb(20, 200, 20)',
  merged: 'rgb(255, 193, 7)'
}

export const composeBorderBottomGradient = selectedSources => {
  let gradient = ''
  const gradientPercentageStep = 100 / selectedSources.length
  let currentStep = 0

  for (const source of selectedSources) {
    gradient += `, ${SourceColor[source]} ${currentStep}%`
    currentStep += gradientPercentageStep
    gradient += `, ${SourceColor[source]} ${currentStep}%`
  }

  // const redStart = 0
  // currentStep += gradientPercentageStep
  // const redEnd = currentStep
  // const greenStart = currentStep
  // currentStep += gradientPercentageStep
  // const greenEnd = currentStep
  // const blueStart = currentStep
  // currentStep += gradientPercentageStep
  // const blueEnd = 100

  return `linear-gradient(to right ${gradient})`
}

const defaultValidSources = ['merged']

export const validateSearchSources = (sources = defaultValidSources) => {
  if (sources.includes('merged')) {
    return defaultValidSources
  }

  const validSources = sources.filter(source => Source.hasOwnProperty(source))

  return validSources.length !== 0 ? validSources : defaultValidSources
}
