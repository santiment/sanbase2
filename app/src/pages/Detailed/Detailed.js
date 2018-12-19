import React from 'react'
import PropTypes from 'prop-types'
import { compose } from 'recompose'
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
import Search from './../../components/Search/SearchContainer'
import ServerErrorMessage from './../../components/ServerErrorMessage'
import EthSpent from './../../pages/EthSpent'
import { calculateBTCVolume, calculateBTCMarketcap } from './../../utils/utils'
import { checkHasPremium, checkIsLoggedIn } from './../UserSelectors'
import DetailedTransactionsTable from './DetailedTransactionsTable'
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
  EmojisSentimentGQL,
  DailyActiveAddressesGQL,
  AllInsightsByTagGQL
} from './DetailedGQL'
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
    error: false,
    errorMessage: ''
  },
  ExchangeFundFlow = {
    exchangeFundsFlow: [],
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
  EmojisSentiment = {
    loading: false,
    error: false,
    emojisSentiment: []
  },
  TwitterHistory = {
    loading: false,
    error: false,
    followersCount: []
  },
  isDesktop,
  isLoggedIn,
  user,
  hasPremium,
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
        ? HistoryPrice.historyPrice
          .filter(item => item.priceUsd > 0)
          .map(item => {
            const priceUsd = +item.priceUsd
            const volume = parseFloat(item.volume)
            const volumeBTC = calculateBTCVolume(item)
            const marketcapBTC = calculateBTCMarketcap(item)
            return { ...item, volumeBTC, marketcapBTC, volume, priceUsd }
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
    items: ExchangeFundFlow.exchangeFundsFlow || []
  }

  const dailyActiveAddresses = {
    loading: DailyActiveAddresses.loading,
    error: DailyActiveAddresses.error,
    items: DailyActiveAddresses.dailyActiveAddresses || []
  }

  const twitterHistory = {
    loading: TwitterHistory.loading,
    error: TwitterHistory.error || false,
    items: TwitterHistory.historyTwitterData || []
  }

  const emojisSentiment = {
    loading: EmojisSentiment.loading,
    error: EmojisSentiment.error,
    items: EmojisSentiment.emojisSentiment || []
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

  const twitterData = {
    loading: TwitterData.loading,
    error: TwitterData.error || false,
    followersCount: (TwitterData.twitterData || {}).followersCount || 0
  }

  const _ethSpentOverTime =
    project.ticker === 'ETH'
      ? ethSpentOverTimeByErc20Projects
      : ethSpentOverTime

  if (Project.error) {
    return <ServerErrorMessage />
  }

  const projectContainerChart = project && (
    <ProjectChartContainer
      routerHistory={history}
      location={location}
      isDesktop={isDesktop}
      {...props}
      price={price}
      github={github}
      burnRate={burnRate}
      tokenDecimals={
        Project.project ? Project.project.tokenDecimals : undefined
      }
      transactionVolume={transactionVolume}
      ethSpentOverTime={_ethSpentOverTime}
      dailyActiveAddresses={dailyActiveAddresses}
      exchangeFundFlow={exchangeFundFlow}
      emojisSentiment={emojisSentiment}
      twitterHistory={twitterHistory}
      twitterData={twitterData}
      ethPrice={ethPrice}
      isERC20={project.isERC20}
      isPremium={hasPremium}
      project={project}
      ticker={project.ticker}
    />
  )

  return (
    <div className='page detailed'>
      <Helmet>
        <title>
          {Project.loading
            ? 'SANbase...'
            : `${Project.project.ticker} project page`}
        </title>
      </Helmet>
      {!isDesktop && <Search />}
      <DetailedHeader
        isDesktop={isDesktop}
        {...Project}
        isLoggedIn={isLoggedIn}
      />
      {isDesktop ? (
        <div className='information'>
          <Panel zero>{projectContainerChart}</Panel>
        </div>
      ) : (
        <div>{projectContainerChart}</div>
      )}
      {project.slug === 'ethereum' && <EthSpent />}
      <div className='information'>
        <PanelBlock isLoading={Project.loading} title='General Info'>
          <GeneralInfoBlock {...Project.project} />
        </PanelBlock>
        <PanelBlock isLoading={Project.loading} title='Financials'>
          <FinancialsBlock {...Project.project} />
        </PanelBlock>
      </div>
      {isDesktop &&
        project.isERC20 &&
        project.tokenTopTransactions &&
        project.tokenTopTransactions.length > 0 && (
        <div className='information'>
          <DetailedTransactionsTable
            Project={Project}
            title={'Top Token Transactions 30D'}
            show={'tokenTopTransactions'}
          />
        </div>
      )}
      {isDesktop &&
        project.isERC20 &&
        project.ethTopTransactions &&
        project.ethTopTransactions.length > 0 && (
        <div className='information'>
          <DetailedTransactionsTable
            Project={Project}
            show={'ethTopTransactions'}
          />
        </div>
      )}
    </div>
  )
}

Detailed.propTypes = propTypes

const mapStateToProps = state => {
  return {
    user: state.user,
    hasPremium: checkHasPremium(state),
    isLoggedIn: checkIsLoggedIn(state),
    timeFilter: state.detailedPageUi.timeFilter
  }
}

const enhance = compose(
  connect(mapStateToProps),
  withApollo,
  graphql(projectBySlugGQL, {
    name: 'Project',
    props: ({ Project }) => ({
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
    options: ({ match }) => {
      const to = moment()
        .endOf('day')
        .utc()
        .format()
      const fromOverTime = moment()
        .subtract(2, 'years')
        .utc()
        .format()
      const interval = moment(to).diff(fromOverTime, 'days') > 300 ? '7d' : '1d'
      return {
        variables: {
          slug: match.params.slug,
          from: moment()
            .subtract(30, 'days')
            .utc()
            .format(),
          to,
          fromOverTime,
          interval
        }
      }
    }
  }),
  graphql(TwitterHistoryGQL, {
    name: 'TwitterHistory',
    skip: ({ timeFilter, Project }) => {
      const { from } = timeFilter
      const ticker = Project.project.ticker
      return !from || !ticker
    },
    options: ({ timeFilter, Project }) => {
      const { from, to } = timeFilter
      const ticker = Project.project.ticker
      return {
        variables: {
          ticker,
          from,
          to,
          interval: ''
        }
      }
    }
  }),
  graphql(HistoryPriceGQL, {
    name: 'EthPrice',
    skip: ({ timeFilter }) => {
      const { from } = timeFilter
      return !from
    },
    options: ({ timeFilter }) => {
      const { from, to } = timeFilter
      return {
        variables: {
          slug: 'ethereum',
          from,
          to
        }
      }
    }
  }),
  graphql(TwitterDataGQL, {
    name: 'TwitterData',
    skip: ({ Project }) => {
      const ticker = Project.project.ticker
      return !ticker
    },
    options: ({ Project }) => {
      const ticker = Project.project.ticker
      return {
        errorPolicy: 'all',
        variables: {
          ticker
        }
      }
    }
  }),
  graphql(HistoryPriceGQL, {
    name: 'HistoryPrice',
    skip: ({ timeFilter, match }) => {
      const { from } = timeFilter
      const slug = match.params.slug
      return !from || !slug
    },
    options: ({ timeFilter, match }) => {
      const { from, to } = timeFilter
      const slug = match.params.slug
      return {
        errorPolicy: 'all',
        variables: {
          from,
          to,
          slug
        }
      }
    }
  }),
  graphql(BurnRateGQL, {
    name: 'BurnRate',
    skip: ({ timeFilter, match }) => {
      const { from } = timeFilter
      const slug = match.params.slug
      return !from || !slug
    },
    options: ({ timeFilter, match }) => {
      const { from, to } = timeFilter
      const slug = match.params.slug
      return {
        errorPolicy: 'all',
        variables: {
          from,
          to,
          slug,
          interval: ''
        }
      }
    }
  }),
  graphql(GithubActivityGQL, {
    name: 'GithubActivity',
    skip: ({ timeFilter, match }) => {
      const { from } = timeFilter
      const slug = match.params.slug
      return !from || !slug
    },
    options: ({ timeFilter, match }) => {
      const { from, to } = timeFilter
      const slug = match.params.slug
      return {
        variables: {
          from: from ? moment(from).subtract(7, 'days') : undefined,
          to,
          slug,
          interval: '',
          transform: 'movingAverage',
          movingAverageIntervalBase: '1w'
        }
      }
    }
  }),
  graphql(TransactionVolumeGQL, {
    name: 'TransactionVolume',
    skip: ({ timeFilter, match }) => {
      const { from } = timeFilter
      const slug = match.params.slug
      return !from || !slug
    },
    options: ({ timeFilter, match }) => {
      const { from, to } = timeFilter
      const slug = match.params.slug
      return {
        errorPolicy: 'all',
        variables: {
          from,
          to,
          slug,
          interval: ''
        }
      }
    }
  }),
  graphql(ExchangeFundFlowGQL, {
    name: 'ExchangeFundFlow',
    skip: ({ timeFilter, match, Project }) => {
      const { from } = timeFilter
      const slug = match.params.slug
      return !from || !slug || (Project && Project.isERC20)
    },
    options: ({ timeFilter, match }) => {
      const { from, to } = timeFilter
      const slug = match.params.slug
      return {
        errorPolicy: 'all',
        variables: {
          from,
          to,
          slug,
          interval: ''
        }
      }
    }
  }),
  graphql(EthSpentOverTimeByErc20ProjectsGQL, {
    name: 'EthSpentOverTimeByErc20Projects',
    skip: ({ timeFilter, match }) => {
      const { from } = timeFilter
      const slug = match.params.slug
      return !from || slug !== 'ethereum'
    },
    options: ({ timeFilter }) => {
      const { from, to } = timeFilter
      return {
        errorPolicy: 'all',
        variables: {
          from,
          to,
          interval: moment(to).diff(from, 'days') > 300 ? '7d' : '1d'
        }
      }
    }
  }),
  graphql(EmojisSentimentGQL, {
    name: 'EmojisSentiment',
    skip: ({ timeFilter, hasPremium, match }) => {
      const { from } = timeFilter
      const slug = match.params.slug
      return !from || !hasPremium || (slug !== 'bitcoin' && slug !== 'ethereum')
    },
    options: ({ timeFilter }) => {
      const { from, to } = timeFilter
      return {
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
    skip: ({ timeFilter, match }) => {
      const { from } = timeFilter
      const slug = match.params.slug
      return !from || !slug
    },
    options: ({ timeFilter, match }) => {
      const { from, to } = timeFilter
      const slug = match.params.slug
      return {
        errorPolicy: 'all',
        variables: {
          from,
          to,
          slug,
          interval: ''
        }
      }
    }
  }),
  graphql(AllInsightsByTagGQL, {
    name: 'AllInsights',
    props: ({ AllInsights }) => ({
      Insights: {
        loading: AllInsights.loading,
        error: AllInsights.error || false,
        items: (AllInsights.allInsightsByTag || []).filter(
          insight => insight.readyState === 'published'
        )
      }
    }),
    skip: ({ isLoggedIn, Project: { project = {} } }) => {
      const { ticker } = project
      return !ticker || !isLoggedIn
    },
    options: ({ isLoggedIn, match, Project: { project = {} } }) => {
      const { ticker } = project
      return {
        errorPolicy: 'all',
        variables: {
          tag: ticker
        }
      }
    }
  })
)

export default enhance(Detailed)
