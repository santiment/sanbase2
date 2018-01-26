import React from 'react'
import PropTypes from 'prop-types'
import { connect } from 'react-redux'
import {
  compose,
  lifecycle,
  withState,
  pure
} from 'recompose'
import { FadeIn } from 'animate-components'
import { Redirect } from 'react-router-dom'
import gql from 'graphql-tag'
import { graphql } from 'react-apollo'
import { retrieveProjects } from './Cashflow.actions.js'
import ProjectIcon from './../components/ProjectIcon'
import PanelBlock from './../components/PanelBlock'
import GeneralInfoBlock from './../components/GeneralInfoBlock'
import FinancialsBlock from './../components/FinancialsBlock'
import ProjectChartContainer from './../components/ProjectChart/ProjectChartContainer'
import Panel from './../components/Panel'
import Search from './../components/Search'
import PercentChanges from './../components/PercentChanges'
import PageLoader from './../components/PageLoader'
import { formatNumber, formatBTC } from '../utils/formatting'
import './Detailed.css'

const propTypes = {
  match: PropTypes.object.isRequired,
  projects: PropTypes.array.isRequired,
  loading: PropTypes.bool.isRequired,
  generalInfo: PropTypes.object
}

export const HiddenElements = () => ''

export const calculateBTCVolume = ({volume, priceUsd, priceBtc}) => {
  return parseFloat(volume) / parseFloat(priceUsd) * parseFloat(priceBtc)
}

export const calculateBTCMarketcap = ({marketcap, priceUsd, priceBtc}) => {
  return parseFloat(marketcap) / parseFloat(priceUsd) * parseFloat(priceBtc)
}

const getProjectByTicker = (match, projects) => {
  const selectedTicker = match.params.ticker
  const project = projects.find(el => {
    const ticker = el.ticker || ''
    return ticker.toLowerCase() === selectedTicker
  })
  return project
}

export const Detailed = ({
  match,
  history,
  location,
  projects,
  loading,
  PriceQuery,
  TwitterData = {
    loading: true,
    error: false,
    twitterData: []
  },
  TwitterHistoryData = {
    loading: true,
    error: false,
    twitterHistoryData: []
  },
  HistoryPrice = {
    loading: true,
    error: false,
    historyPrice: []
  },
  GithubActivity = {
    loading: true,
    error: false,
    githubActivity: []
  },
  BurnRate = {
    loading: true,
    error: false,
    burnRate: []
  },
  TransactionVolume = {
    loading: true,
    error: false,
    transactionVolume: []
  },
  user,
  generalInfo,
  changeChartVars,
  isDesktop
}) => {
  if (loading) {
    return (
      <PageLoader />
    )
  }
  const project = getProjectByTicker(match, projects)

  if (!project) {
    return (
      <Redirect to={{
        pathname: '/'
      }} />
    )
  }

  const twitter = {
    history: {
      error: TwitterHistoryData.error || false,
      loading: TwitterHistoryData.loading,
      items: TwitterHistoryData.historyTwitterData || []
    },
    data: {
      error: TwitterData.error || false,
      loading: TwitterData.loading,
      followersCount: TwitterData.twitterData
        ? TwitterData.twitterData.followersCount
        : undefined
    }
  }

  const price = {
    history: {
      loading: HistoryPrice.loading,
      items: HistoryPrice.historyPrice
        ? HistoryPrice.historyPrice.map(item => {
          const volumeBTC = calculateBTCVolume(item)
          const marketcapBTC = calculateBTCMarketcap(item)
          return {...item, volumeBTC, marketcapBTC}
        })
        : []
    }
  }

  const github = {
    history: {
      loading: GithubActivity.loading,
      items: GithubActivity.githubActivity || []
    }
  }

  const burnRate = {
    loading: BurnRate.loading,
    error: BurnRate.error || false,
    items: BurnRate.burnRate || []
  }

  const transactionVolume = {
    loading: TransactionVolume.loading,
    error: TransactionVolume.error || false,
    items: TransactionVolume.transactionVolume || []
  }

  const projectContainerChart = <ProjectChartContainer
    routerHistory={history}
    location={location}
    isDesktop={isDesktop}
    twitter={twitter}
    price={price}
    github={github}
    burnRate={burnRate}
    tokenDecimals={generalInfo.project ? generalInfo.project.tokenDecimals : undefined}
    transactionVolume={transactionVolume}
    onDatesChange={(from, to, interval, ticker) => {
      changeChartVars({
        from,
        to,
        interval,
        ticker
      })
    }}
    ticker={project.ticker} />

  return (
    <div className='page detailed'>
      {!isDesktop &&
        <Search
          onSelectProject={ticker => history.push(`/projects/${ticker.toLowerCase()}`)}
          projects={projects} />}
      <FadeIn duration='0.7s' timingFunction='ease-in' as='div'>
        <div className='detailed-head'>
          <div className='detailed-name'>
            <h1>{project.name}</h1>
            <ProjectIcon
              name={project.name}
              size={24} />
            <div className='detailed-ticker-name'>
              {project.ticker.toUpperCase()}
            </div>
          </div>

          {!PriceQuery.loading && PriceQuery.price &&
            <div className='detailed-price'>
              <div className='detailed-price-description'>Today's changes</div>
              <div className='detailed-price-usd'>
                {formatNumber(PriceQuery.price.priceUsd, 'USD')}&nbsp;
                {!generalInfo.isLoading && generalInfo.project &&
                  <PercentChanges changes={generalInfo.project.percentChange24h} />}
              </div>
              <div className='detailed-price-btc'>
                BTC {formatBTC(parseFloat(PriceQuery.price.priceBtc))}
              </div>
            </div>}

          <HiddenElements>
            <div className='detailed-buttons'>
              <button className='add-to-dashboard'>
                <i className='fa fa-plus' />
                &nbsp; Add to Dashboard
              </button>
            </div>
          </HiddenElements>
        </div>
        {isDesktop
          ? <Panel zero>{projectContainerChart}</Panel>
          : <div>{projectContainerChart}</div>}
        <div className='information'>
          <PanelBlock
            isUnauthorized={generalInfo.isUnauthorized}
            isLoading={generalInfo.isLoading || PriceQuery.loading}
            title='General Info'>
            <GeneralInfoBlock {...generalInfo.project} />
          </PanelBlock>
          <PanelBlock
            isUnauthorized={generalInfo.isUnauthorized}
            isLoading={generalInfo.isLoading}
            title='Financials'>
            <FinancialsBlock
              ethPrice={project.ethPrice}
              wallets={project.wallets}
              {...generalInfo.project} />
          </PanelBlock>
        </div>
      </FadeIn>
    </div>
  )
}

Detailed.propTypes = propTypes

const mapStateToProps = state => {
  return {
    user: state.user,
    projects: state.projects.items,
    loading: state.projects.isLoading,
    generalInfo: {
      isLoading: false,
      isUnauthorized: !state.user.token
    }
  }
}

const mapDispatchToProps = dispatch => {
  return {
    // TODO: have to retrive only selected project
    retrieveProjects: () => dispatch(retrieveProjects)
  }
}

const queryPrice = gql`
  query queryPrice($ticker: String!) {
    price (
      ticker: $ticker
    ) {
      priceBtc,
      priceUsd,
      volume,
      datetime,
      marketcap
    }
}`

const queryProject = gql`
  query queryProject($id: ID!) {
    project(
      id: $id,
    ){
      id,
      name,
      ticker,
      websiteLink,
      facebookLink,
      githubLink,
      redditLink,
      twitterLink,
      whitepaperLink,
      slackLink,
      btcBalance,
      projectTransparency,
      projectTransparencyDescription,
      projectTransparencyStatus,
      tokenAddress,
      fundsRaisedIcos { amount, currencyCode },
      roiUsd,
      priceUsd,
      volumeUsd,
      ethBalance,
      marketcapUsd,
      tokenDecimals,
      rank,
      totalSupply,
      percentChange24h,
    }
  }
`
const queryTwitterHistory = gql`
  query queryTwitterHistory($ticker:String, $from: DateTime, $to: DateTime, $interval: String) {
    historyTwitterData(
      ticker: $ticker,
      from: $from,
      to: $to,
      interval: $interval
    ) {
      datetime
      followersCount
      __typename
    }
  }
`

const queryTwitterData = gql`
  query queryTwitterData($ticker:String) {
    twitterData(ticker: $ticker) {
      datetime
      followersCount
      twitterName
    }
  }
`

const queryHistoryPrice = gql`
  query queryHistoryPrice($ticker: String, $from: DateTime, $to: DateTime, $interval: String) {
    historyPrice(
      ticker: $ticker,
      from: $from,
      to: $to,
      interval: $interval
    ) {
      priceBtc,
      priceUsd,
      volume,
      datetime,
      marketcap
    }
}`

const queryGithubActivity = gql`
  query queryGithubActivity($ticker: String, $from: DateTime, $to: DateTime, $interval: String) {
    githubActivity(
      ticker: $ticker,
      from: $from,
      to: $to,
      interval: $interval
    ) {
      datetime,
      activity
    }
}`

const queryBurnRate = gql`
  query queryBurnRate($ticker:String, $from: DateTime, $to: DateTime) {
    burnRate(
      ticker: $ticker,
      from: $from,
      to: $to
    ) {
      datetime
      burnRate
      __typename
    }
}`

const queryTransactionVolume = gql`
  query queryTransactionVolume($ticker:String, $from: DateTime, $to: DateTime) {
    transactionVolume(
      ticker: $ticker,
      from: $from,
      to: $to
    ) {
      datetime
      transactionVolume
      __typename
    }
}`

const mapDataToProps = ({ProjectQuery}) => {
  const isLoading = ProjectQuery.loading
  const isEmpty = !!ProjectQuery.project
  const isError = !!ProjectQuery.error
  const errorMessage = ProjectQuery.error ? ProjectQuery.error.message : ''
  const isUnauthorized = ProjectQuery.error ? /\bunauthorized/.test(ProjectQuery.error.message) : false
  if (ProjectQuery.error && !isUnauthorized) {
    // If our API server is not reponed with ProjectQuery
    throw new Error(ProjectQuery.error.message)
  }
  const project = ProjectQuery.project

  return {generalInfo: {isLoading, isEmpty, isError, project, errorMessage, isUnauthorized}}
}

const mapPropsToOptions = ({match, projects, user}) => {
  const project = getProjectByTicker(match, projects)
  return {
    skip: !project,
    errorPolicy: 'all',
    variables: {
      id: project ? project.id : 0
    }
  }
}

const enhance = compose(
  connect(
    mapStateToProps,
    mapDispatchToProps
  ),
  withState('chartVars', 'changeChartVars', {
    from: undefined,
    to: undefined,
    interval: undefined,
    ticker: undefined
  }),
  lifecycle({
    componentDidMount () {
      this.props.retrieveProjects()
    }
  }),
  graphql(queryPrice, {
    name: 'PriceQuery',
    options: ({match, projects}) => {
      const project = getProjectByTicker(match, projects)
      return {
        skip: !project,
        variables: {
          'ticker': project ? project.ticker.toUpperCase() : 'SAN'
        }
      }
    }
  }),
  graphql(queryProject, {
    name: 'ProjectQuery',
    props: mapDataToProps,
    options: mapPropsToOptions
  }),
  graphql(queryTwitterData, {
    name: 'TwitterData',
    options: ({chartVars}) => {
      const { ticker } = chartVars
      return {
        skip: !ticker,
        errorPolicy: 'all',
        variables: {
          ticker
        }
      }
    }
  }),
  graphql(queryTwitterHistory, {
    name: 'TwitterHistoryData',
    options: ({chartVars}) => {
      const {from, to, ticker} = chartVars
      return {
        skip: !from,
        errorPolicy: 'all',
        variables: {
          from,
          to,
          ticker
        }
      }
    }
  }),
  graphql(queryHistoryPrice, {
    name: 'HistoryPrice',
    options: ({chartVars}) => {
      const {from, to, ticker, interval} = chartVars
      return {
        skip: !from,
        errorPolicy: 'all',
        variables: {
          from,
          to,
          ticker,
          interval
        }
      }
    }
  }),
  graphql(queryGithubActivity, {
    name: 'GithubActivity',
    options: ({match, chartVars}) => {
      const {from, to, ticker} = chartVars
      return {
        skip: !from,
        variables: {
          from,
          to,
          ticker,
          interval: '1d'
        }
      }
    }
  }),
  graphql(queryBurnRate, {
    name: 'BurnRate',
    options: ({chartVars}) => {
      const {from, to, ticker} = chartVars
      return {
        skip: !from,
        errorPolicy: 'all',
        variables: {
          from,
          to,
          ticker
        }
      }
    }
  }),
  graphql(queryTransactionVolume, {
    name: 'TransactionVolume',
    options: ({chartVars}) => {
      const {from, to, ticker} = chartVars
      return {
        skip: !from,
        errorPolicy: 'all',
        variables: {
          from,
          to,
          ticker
        }
      }
    }
  }),
  pure
)

export default enhance(Detailed)
