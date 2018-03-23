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
import PanelBlock from './../../components/PanelBlock'
import GeneralInfoBlock from './GeneralInfoBlock'
import FinancialsBlock from './FinancialsBlock'
import ProjectChartContainer from './../../components/ProjectChart/ProjectChartContainer'
import Panel from './../../components/Panel'
import Search from './../../components/SearchContainer'
import {
  calculateBTCVolume,
  calculateBTCMarketcap,
  millify
} from '../../utils/utils'
import { isERC20 } from './../Projects/projectSelectors'
import DetailedHeader from './DetailedHeader'
import {
  projectBySlugGQL,
  TwitterDataGQL,
  TwitterHistoryGQL,
  HistoryPriceGQL,
  BurnRateGQL,
  GithubActivityGQL,
  TransactionVolumeGQL,
  ExchangeFundFlowGQL,
  EthSpentOverTimeByErc20ProjectsGQL
} from './DetailedGQL'
import SpentOverTime from './SpentOverTime'
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
  changeChartVars,
  isDesktop
}) => {
  const project = Project.project

  if (/not found/.test(Project.errorMessage)) {
    return <Redirect to='/' />
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
      twitter={twitter}
      price={price}
      github={github}
      burnRate={burnRate}
      tokenDecimals={Project.project ? Project.project.tokenDecimals : undefined}
      transactionVolume={transactionVolume}
      ethSpentOverTime={_ethSpentOverTime}
      isERC20={project.isERC20}
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
      <Helmet>
        <title>{Project.loading
          ? 'SANbase...'
          : `${Project.project.ticker} project page`}
        </title>
      </Helmet>
      {!isDesktop && <Search />}
      <DetailedHeader {...Project} />
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
        {project.isERC20 &&
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
                  <a href={`https://etherscan.io/address/${transaction.trxHash}`}>{transaction.trxHash}</a>
                </div>
                <div>
                  {millify(parseFloat(parseFloat(transaction.trxValue).toFixed(2)))}
                  &nbsp; | &nbsp;
                  {moment(transaction.datetime).fromNow()}
                </div>
              </div>
            ))}
          </div>
        </PanelBlock>}
        {project.ethSpentOverTime && project.ethSpentOverTime.length > 0 &&
          <SpentOverTime project={project} loading={Project.loading} />}
      </div>
    </div>
  )
}

Detailed.propTypes = propTypes

const enhance = compose(
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
          isERC20: isERC20(Project.projectBySlug)
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
  graphql(TwitterHistoryGQL, {
    name: 'TwitterHistoryData',
    options: ({chartVars}) => {
      const {from, to, ticker} = chartVars
      return {
        skip: !from || !ticker,
        errorPolicy: 'all',
        variables: {
          from,
          to,
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
      return {
        skip: !from || !ticker,
        errorPolicy: 'all',
        variables: {
          from,
          to,
          ticker
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
      return {
        skip: !from || !ticker,
        errorPolicy: 'all',
        variables: {
          from,
          to,
          ticker
        }
      }
    }
  }),
  graphql(ExchangeFundFlowGQL, {
    name: 'ExchangeFundFlow',
    options: ({chartVars}) => {
      const {from, to, ticker} = chartVars
      return {
        skip: !from || !ticker,
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
  })
)

export default enhance(Detailed)
