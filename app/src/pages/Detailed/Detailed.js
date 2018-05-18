import React from 'react'
import PropTypes from 'prop-types'
import {
  compose,
  withState
} from 'recompose'
import { Redirect } from 'react-router-dom'
import moment from 'moment'
import { Helmet } from 'react-helmet'
import { graphql, withApollo } from 'react-apollo'
import { connect } from 'react-redux'
import GeneralInfoBlock from './GeneralInfoBlock'
import FinancialsBlock from './FinancialsBlock'
import DetailedHeader from './DetailedHeader'
import ProjectChartContainer from './../../components/ProjectChart/ProjectChartContainer'
import PanelBlock from './../../components/PanelBlock'
import Panel from './../../components/Panel'
import Search from './../../components/SearchContainer'
import { calculateBTCVolume, calculateBTCMarketcap } from './../../utils/utils'
import { millify } from './../../utils/formatting'
import {
  projectBySlugGQL,
  TwitterDataGQL,
  TwitterHistoryGQL,
  HistoryPriceGQL,
  BurnRateGQL,
  GithubActivityGQL,
  TransactionVolumeGQL,
  ExchangeFundFlowGQL,
  EthSpentOverTimeByErc20ProjectsGQL,
  DailyActiveAddressesGQL,
  FollowProjectGQL,
  UnfollowProjectGQL
} from './DetailedGQL'
import EthereumBlock from './EthereumBlock'
import './Detailed.css'

const propTypes = {
  match: PropTypes.object.isRequired
}

export const Detailed = ({
  match,
  history,
  location,
  TwitterData = {
    loading: true,
    error: false,
    twitterData: []
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
  Project = {
    project: undefined,
    loading: true,
    error: false
  },
  ExchangeFundFlow = {
    transactionVolume: [],
    error: false,
    loading: true
  },
  EthSpentOverTimeByErc20Projects = {
    ethSpentOverTimeByErc20Projects: [],
    loading: true,
    error: false
  },
  EthPrice = {
    loading: true,
    error: false,
    historyPrice: []
  },
  DailyActiveAddresses = {
    loading: true,
    error: false,
    dailyActiveAddresses: []
  },
  followProject,
  unfollowProject,
  changeChartVars,
  isDesktop,
  isLoggedIn,
  dispatch,
  user,
  ...props
}) => {
  const project = Project.project

  if (/not found/.test(Project.errorMessage)) {
    return <Redirect to='/' />
  }

  const price = {
    history: {
      loading: HistoryPrice.loading,
      items: HistoryPrice.historyPrice
        ? HistoryPrice.historyPrice.filter(item => item.priceUsd > 0).map(item => {
          const priceUsd = +item.priceUsd
          const volume = parseFloat(item.volume)
          const volumeBTC = calculateBTCVolume(item)
          const marketcapBTC = calculateBTCMarketcap(item)
          return {...item, volumeBTC, marketcapBTC, volume, priceUsd}
        })
        : []
    }
  }

  const ethPrice = {
    history: {
      loading: EthPrice.loading,
      items: EthPrice.historyPrice ? EthPrice.historyPrice : []
    }
  }

  const github = {
    history: {
      loading: GithubActivity.loading,
      items: GithubActivity.githubActivity || []
    }
  }

  const burnRate = {
    ...BurnRate,
    loading: BurnRate.loading,
    error: BurnRate.error || false,
    items: BurnRate.burnRate || []
  }

  const transactionVolume = {
    loading: TransactionVolume.loading,
    error: TransactionVolume.error || false,
    items: TransactionVolume.transactionVolume || []
  }

  const exchangeFundFlow = {
    loading: ExchangeFundFlow.loading,
    error: ExchangeFundFlow.error,
    items: ExchangeFundFlow.transactionVolume
  }

  const dailyActiveAddresses = {
    loading: DailyActiveAddresses.loading,
    error: DailyActiveAddresses.error,
    items: DailyActiveAddresses.dailyActiveAddresses || []
  }

  const ethSpentOverTimeByErc20Projects = {
    loading: EthSpentOverTimeByErc20Projects.loading,
    error: EthSpentOverTimeByErc20Projects.error,
    items: EthSpentOverTimeByErc20Projects.ethSpentOverTimeByErc20Projects || []
  }

  const ethSpentOverTime = {
    loading: Project.loading,
    error: project.errorMessage || false,
    items: project.ethSpentOverTime || []
  }

  const _ethSpentOverTime = project.ticker === 'ETH'
    ? ethSpentOverTimeByErc20Projects
    : ethSpentOverTime

  const projectContainerChart = project &&
    <ProjectChartContainer
      routerHistory={history}
      location={location}
      isDesktop={isDesktop}
      {...props}
      price={price}
      github={github}
      burnRate={burnRate}
      tokenDecimals={Project.project ? Project.project.tokenDecimals : undefined}
      transactionVolume={transactionVolume}
      ethSpentOverTime={_ethSpentOverTime}
      dailyActiveAddresses={dailyActiveAddresses}
      ethPrice={ethPrice}
      isERC20={project.isERC20}
      project={project}
      onDatesChange={(from, to, interval, ticker) => {
        changeChartVars({
          from,
          to,
          interval,
          ticker
        })
      }}
      ticker={project.ticker} />

  const isFavorite = () => isLoggedIn && project &&
    user.followedProjects && user.followedProjects.includes(project.id)

  return (
    <div className='page detailed'>
      <Helmet>
        <title>{Project.loading
          ? 'SANbase...'
          : `${Project.project.ticker} project page`}
        </title>
      </Helmet>
      {!isDesktop && <Search />}
      <DetailedHeader
        {...Project}
        dispatch={dispatch}
        isFavorite={isFavorite()}
        isLoggedIn={isLoggedIn}
        addToFavorites={followProject}
        removeFromFavorites={unfollowProject}
      />
      {isDesktop
        ? <Panel zero>{projectContainerChart}</Panel>
        : <div>{projectContainerChart}</div>}
      <div className='information'>
        <PanelBlock
          isLoading={Project.loading}
          title='General Info'>
          <GeneralInfoBlock {...Project.project} />
        </PanelBlock>
        <PanelBlock
          isLoading={Project.loading}
          title='Financials'>
          <FinancialsBlock {...Project.project} />
        </PanelBlock>
      </div>
      <div className='information'>
        { project.ticker &&
        project.ticker.toLowerCase() === 'eth' &&
        <EthereumBlock
          project={project}
          loading={Project.loading} />}
        {!exchangeFundFlow.loading &&
          exchangeFundFlow.items &&
          <PanelBlock
            isLoading={false}
            title='Exchange Fund Flows'>
            <div>
              {exchangeFundFlow.items.map((item, index) => (
                <div key={index}>
                  { item }
                </div>
              ))}
            </div>
          </PanelBlock>}
      </div>
      <div className='information'>
        {isDesktop && project.isERC20 &&
        project.ethTopTransactions &&
        project.ethTopTransactions.length > 0 &&
        <PanelBlock
          isLoading={Project.loading}
          title='Top ETH Transactions'>
          <div>
            {project.ethTopTransactions &&
            project.ethTopTransactions.map((transaction, index) => (
              <div className='top-eth-transaction' key={index}>
                <div className='top-eth-transaction__hash'>
                  <a href={`https://etherscan.io/tx/${transaction.trxHash}`}>{transaction.trxHash}</a>
                </div>
                <div>
                  {millify(transaction.trxValue, 2)}
                  &nbsp; | &nbsp;
                  {moment(transaction.datetime).fromNow()}
                </div>
              </div>
            ))}
          </div>
        </PanelBlock>}
      </div>
    </div>
  )
}

Detailed.propTypes = propTypes

const mapStateToProps = state => {
  return {
    user: state.user,
    isLoggedIn: !!state.user.token
  }
}

const enhance = compose(
  connect(
    mapStateToProps
  ),
  withApollo,
  withState('chartVars', 'changeChartVars', {
    from: undefined,
    to: undefined,
    interval: undefined,
    ticker: undefined
  }),
  graphql(projectBySlugGQL, {
    name: 'Project',
    props: ({Project}) => ({
      Project: {
        loading: Project.loading,
        empty: !Project.hasOwnProperty('project'),
        error: Project.error,
        errorMessage: Project.error ? Project.error.message : '',
        project: {
          ...Project.projectBySlug,
          isERC20: (Project.projectBySlug || {}).infrastructure === 'ETH'
        }
      }
    }),
    options: ({match}) => {
      const to = moment().endOf('day').utc().format()
      const fromOverTime = moment().subtract(2, 'years').utc().format()
      const interval = moment(to).diff(fromOverTime, 'days') > 300 ? '7d' : '1d'
      return {
        variables: {
          slug: match.params.slug,
          from: moment().subtract(30, 'days').utc().format(),
          to,
          fromOverTime,
          interval
        }
      }
    }
  }),
  graphql(TwitterHistoryGQL, {
    name: 'TwitterHistory',
    options: ({chartVars}) => {
      const {from, to, ticker, interval} = chartVars
      return {
        skip: !ticker,
        variables: {
          ticker: 'ETH',
          from,
          to,
          interval
        }
      }
    }
  }),
  graphql(HistoryPriceGQL, {
    name: 'EthPrice',
    options: ({chartVars, Project}) => {
      const {from, to, ticker, interval} = chartVars
      return {
        skip: !ticker,
        variables: {
          ticker: 'ETH',
          from,
          to,
          interval
        }
      }
    }
  }),
  graphql(TwitterDataGQL, {
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
  graphql(HistoryPriceGQL, {
    name: 'HistoryPrice',
    options: ({chartVars}) => {
      const {from, to, ticker, interval} = chartVars
      return {
        skip: !from || !ticker,
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
  graphql(BurnRateGQL, {
    name: 'BurnRate',
    options: ({chartVars, Project}) => {
      const {from, to, ticker} = chartVars
      const interval = moment(to).diff(from, 'days') > 300 ? '7d' : '1d'
      return {
        skip: !from || !ticker,
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
  graphql(GithubActivityGQL, {
    name: 'GithubActivity',
    options: ({chartVars}) => {
      const {from, to, ticker} = chartVars
      return {
        skip: !from || !ticker,
        variables: {
          from: from ? moment(from).subtract(7, 'days') : undefined,
          to,
          ticker,
          interval: '1d',
          transform: 'movingAverage',
          movingAverageInterval: 7
        }
      }
    }
  }),
  graphql(TransactionVolumeGQL, {
    name: 'TransactionVolume',
    options: ({chartVars, Project}) => {
      const {from, to, ticker} = chartVars
      const interval = moment(to).diff(from, 'days') > 300 ? '7d' : '1d'
      return {
        skip: !from || !ticker,
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
  graphql(ExchangeFundFlowGQL, {
    name: 'ExchangeFundFlow',
    options: ({chartVars, Project}) => {
      const {from, to, ticker} = chartVars
      return {
        skip: !from || !ticker || (Project && !Project.isERC20),
        errorPolicy: 'all',
        variables: {
          from,
          to,
          ticker
        }
      }
    }
  }),
  graphql(EthSpentOverTimeByErc20ProjectsGQL, {
    name: 'EthSpentOverTimeByErc20Projects',
    options: ({chartVars, Project}) => {
      const {from, to, ticker} = chartVars
      return {
        skip: !from || ticker !== 'ETH',
        errorPolicy: 'all',
        variables: {
          from,
          to,
          interval: moment(to).diff(from, 'days') > 300 ? '7d' : '1d'
        }
      }
    }
  }),
  graphql(DailyActiveAddressesGQL, {
    name: 'DailyActiveAddresses',
    options: ({chartVars}) => {
      const {from, to, ticker} = chartVars
      return {
        skip: !from || !ticker,
        errorPolicy: 'all',
        variables: {
          from,
          to,
          ticker,
          interval: moment(to).diff(from, 'days') > 300 ? '7d' : '1d'
        }
      }
    }
  }),
  graphql(FollowProjectGQL, {
    name: 'followProject'
  }),
  graphql(UnfollowProjectGQL, {
    name: 'unfollowProject'
  })
)

export default enhance(Detailed)
