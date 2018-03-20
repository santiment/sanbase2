import React from 'react'
import PropTypes from 'prop-types'
import {
  compose,
  lifecycle,
  withState
} from 'recompose'
import moment from 'moment'
import { Redirect } from 'react-router-dom'
import { Helmet } from 'react-helmet'
import { graphql, withApollo } from 'react-apollo'
import PanelBlock from './../../components/PanelBlock'
import GeneralInfoBlock from './GeneralInfoBlock'
import FinancialsBlock from './FinancialsBlock'
import ProjectChartContainer from './../../components/ProjectChart/ProjectChartContainer'
import Panel from './../../components/Panel'
import Search from './../../components/SearchContainer'
import { calculateBTCVolume, calculateBTCMarketcap } from '../../utils/utils'
import allProjectsGQL from './../Projects/allProjectsGQL'
import { isERC20 } from './../Projects/projectSelectors'
import DetailedHeader from './DetailedHeader'
import {
  projectGQL,
  TwitterDataGQL,
  TwitterHistoryGQL,
  HistoryPriceGQL,
  BurnRateGQL,
  GithubActivityGQL,
  TransactionVolumeGQL
} from './DetailedGQL'
import './Detailed.css'

const propTypes = {
  match: PropTypes.object.isRequired
}

const getProjectIDByTicker = (match, allProjects = null) => {
  const selectedTicker = match.params.ticker
  const project = (allProjects || []).find(el => {
    const ticker = el.ticker || ''
    return ticker.toLowerCase() === selectedTicker
  })
  return parseInt((project || {}).id, 10) || null
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
  changeChartVars,
  isDesktop,
  projectId = -1,
  projects = []
}) => {
  const project = Project.project
  if (!projectId) {
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
  withState('projectId', 'changeProjectId', undefined),
  withState('projects', 'changeProjects', []),
  lifecycle({
    componentDidMount () {
      this.props.client.query({
        query: allProjectsGQL
      }).then(response => {
        const id = getProjectIDByTicker(this.props.match, response.data.allProjects)
        this.props.changeProjectId(id)
        this.props.changeProjects(response.data.allProjects)
      })
    },
    componentDidUpdate (prevProps, prevState) {
      if (this.props.match.params.ticker !== prevProps.match.params.ticker &&
        this.props.projects.length > 0) {
        console.log(this.props)
        const id = getProjectIDByTicker(this.props.match, this.props.projects)
        this.props.changeProjectId(id)
      }
    }
  }),
  graphql(projectGQL, {
    name: 'Project',
    props: ({Project}) => ({
      Project: {
        loading: Project.loading,
        empty: !Project.hasOwnProperty('project'),
        error: Project.error,
        errorMessage: Project.error ? Project.error.message : '',
        project: {
          ...Project.project,
          isERC20: isERC20(Project.project)
        }
      }
    }),
    options: ({projectId}) => ({
      skip: !projectId,
      errorPolicy: 'all',
      variables: {
        id: projectId
      }
    })
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
  graphql(GithubActivityGQL, {
    name: 'GithubActivity',
    options: ({match, chartVars}) => {
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
  graphql(BurnRateGQL, {
    name: 'BurnRate',
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
  graphql(TransactionVolumeGQL, {
    name: 'TransactionVolume',
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
  })
)

export default enhance(Detailed)
