import React from 'react'
import moment from 'moment'
import { graphql } from 'react-apollo'
import { connect } from 'react-redux'
import { compose } from 'recompose'
import { selectTimeRange } from './AssetsChart.reducers.js'
import { calculateBTCVolume, calculateBTCMarketcap } from './../../utils/utils'
import { projectBySlugGQL, historyPriceGQL } from './gql'

class AssetsChartContainer extends React.Component {
  componentDidMount () {
    this.props.handleSelectTimeRange({ timeRange: 'all' })
  }

  render () {
    const {
      render,
      Project = {},
      History = {
        items: [],
        isLoading: false,
        isEmpty: true
      },
      currency,
      ...rest
    } = this.props

    return render({ Project, History, currency, ...rest })
  }
}

const mapStateToProps = ({ assetsChart }) => ({
  timeRange: assetsChart.timeRange,
  from: assetsChart.from,
  to: assetsChart.to,
  interval: assetsChart.interval,
  currency: assetsChart.currency,
  settings: {
    isToggledVolume: assetsChart.isToggledVolume
  }
})

const mapDispatchToProps = dispatch => ({
  handleSelectTimeRange: props => dispatch(selectTimeRange(props))
})

const mapDataToProps = ({ Project }) => ({
  Project: {
    isLoading: Project.loading,
    isEmpty: !Project.hasOwnProperty('project'),
    isError: Project.error,
    errorMessage: Project.error ? Project.error.message : '',
    project: {
      ...Project.projectBySlug,
      isERC20: (Project.projectBySlug || {}).infrastructure === 'ETH'
    }
  }
})

const mapHistoryPriceDataToProps = ({ HistoryPrice }) => {
  const items = HistoryPrice.historyPrice
    ? HistoryPrice.historyPrice.filter(item => item.priceUsd > 0).map(item => {
      const priceUsd = +item.priceUsd
      const volume = parseFloat(item.volume)
      const volumeBTC = calculateBTCVolume(item)
      const marketcapBTC = calculateBTCMarketcap(item)
      return {
        ...item,
        volumeBTC,
        marketcapBTC,
        volume,
        priceUsd
      }
    })
    : []
  return {
    History: {
      items,
      isLoading: HistoryPrice.loading,
      isEmpty: items.length === 0
    }
  }
}

const enhance = compose(
  connect(
    mapStateToProps,
    mapDispatchToProps
  ),
  graphql(projectBySlugGQL, {
    name: 'Project',
    props: mapDataToProps,
    options: ({ slug }) => {
      const to = moment()
        .endOf('day')
        .utc()
        .format()
      const from = moment()
        .subtract(30, 'days')
        .utc()
        .format()
      const fromOverTime = moment()
        .subtract(2, 'years')
        .utc()
        .format()
      const interval = moment(to).diff(fromOverTime, 'days') > 300 ? '7d' : '1d'
      return {
        variables: {
          slug,
          from,
          to,
          fromOverTime,
          interval
        }
      }
    }
  }),
  graphql(historyPriceGQL, {
    name: 'HistoryPrice',
    props: mapHistoryPriceDataToProps,
    skip: ({ from, slug }) => !from || !slug,
    options: ({ from, to, slug }) => ({
      errorPolicy: 'all',
      variables: {
        from,
        to,
        slug
      }
    })
  })
)

export default enhance(AssetsChartContainer)
