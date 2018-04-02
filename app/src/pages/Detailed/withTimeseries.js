import { compose } from 'recompose'
import { graphql } from 'react-apollo'

const makeProps = (name, chartjs = {}) => props => {
  const Data = props[name] || {}
  return {
    [name]: {
      dataset: chartjs.dataset || undefined,
      scale: chartjs.scale || undefined,
      loading: Data.loading || false,
      error: Data.error || false,
      errorMessage: Data.error ? Data.error.message : '',
      items: Data[name] || [],
      ...Data
    }
  }
}

const makeOptions = (name, options) => props => {
  return {
    skip: !props.chartVars.ticker,
    errorPolicy: 'all',
    variables: options(props).variables
  }
}

const makeRequestFromTimeSeries = ({query, name, options, chartjs}) => {
  return graphql(query, {
    name,
    props: makeProps(name, chartjs),
    options: makeOptions(name, options)
  })
}

const withTimeseries = (...timeseries) => WrappedComponent => {
  return compose(
    ...timeseries.reduce((acc, item) => {
      return [(makeRequestFromTimeSeries(item)), ...acc]
    }, [])
  )(WrappedComponent)
}

export default withTimeseries
