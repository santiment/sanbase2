import React from 'react'
import PropTypes from 'prop-types'
import { connect } from 'react-redux'
import {
  compose,
  lifecycle
} from 'recompose'
import { Merge, FadeIn } from 'animate-components'
import { fadeIn, slideRight } from 'animate-keyframes'
import { Redirect } from 'react-router-dom'
import { Tab, Tabs, TabList, TabPanel } from 'react-tabs'
import gql from 'graphql-tag'
import { graphql } from 'react-apollo'
import { retrieveProjects } from './Cashflow.actions.js'
import ProjectIcon from './../components/ProjectIcon'
import PanelBlock from './../components/PanelBlock'
import GeneralInfoBlock from './../components/GeneralInfoBlock'
import FinancialsBlock from './../components/FinancialsBlock'
import ProjectChartContainer from './../components/ProjectChart/ProjectChartContainer'
import { formatNumber, formatBTC } from '../utils/formatting'
import Panel from './../components/Panel'
import './Detailed.css'

const propTypes = {
  match: PropTypes.object.isRequired,
  projects: PropTypes.array.isRequired,
  loading: PropTypes.bool.isRequired,
  generalInfo: PropTypes.object
}

export const HiddenElements = () => ''

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
  projects,
  loading,
  PriceQuery,
  generalInfo
}) => {
  if (loading) {
    return (
      <div className='page detailed'>
        <h2>Loading...</h2>
      </div>
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

  return (
    <div className='page detailed'>
      <FadeIn duration='0.7s' timingFunction='ease-in' as='div'>
        <div className='detailed-head'>
          <div className='detailed-name'>
            <h1><ProjectIcon name={project.name} size={28} /> {project.name} ({project.ticker.toUpperCase()})</h1>
            <p>Manage entire organisations using the blockchain.</p>
          </div>

          {!PriceQuery.loading && PriceQuery.price &&
            <Merge
              one={{ name: fadeIn, duration: '0.3s', timingFunction: 'ease-in' }}
              two={{ name: slideRight, duration: '0.5s', timingFunction: 'ease-out' }}
              as='div'
            >
              <div className='detailed-price'>
                <div>{formatNumber(PriceQuery.price.priceUsd, 'USD')}</div>
                <div>BTC {formatBTC(parseFloat(PriceQuery.price.priceBtc))}</div>
              </div>
            </Merge>}

          <HiddenElements>
            <div className='detailed-buttons'>
              <button className='add-to-dashboard'>
                <i className='fa fa-plus' />
                &nbsp; Add to Dashboard
              </button>
            </div>
          </HiddenElements>
        </div>
        <Panel withoutHeader>
          <ProjectChartContainer ticker={project.ticker} />
        </Panel>
        <HiddenElements>
          <div className='panel'>
            <Tabs className='activity-panel'>
              <TabList className='nav'>
                <Tab className='nav-item' selectedClassName='active'>
                  <button className='nav-link'>
                    Social Mentions
                  </button>
                </Tab>
                <Tab className='nav-item' selectedClassName='active'>
                  <button className='nav-link'>
                    Social Activity over Time
                  </button>
                </Tab>
                <Tab className='nav-item' selectedClassName='active'>
                  <button className='nav-link'>
                    Sentiment/Intensity
                  </button>
                </Tab>
                <Tab className='nav-item' selectedClassName='active'>
                  <button className='nav-link'>
                    Github Activity
                  </button>
                </Tab>
                <Tab className='nav-item' selectedClassName='active'>
                  <button className='nav-link'>
                    SAN Community
                  </button>
                </Tab>
              </TabList>
              <TabPanel>
                Social Mentions
              </TabPanel>
              <TabPanel>
                Social Activity over Time
              </TabPanel>
              <TabPanel>
                Sentiment/Intensity
              </TabPanel>
              <TabPanel>
                Github Activity
              </TabPanel>
              <TabPanel>
                SAN Community
              </TabPanel>
            </Tabs>
          </div>
        </HiddenElements>
        <HiddenElements>
          <PanelBlock title='Blockchain Analytics' />
          <div className='analysis'>
            <PanelBlock title='Signals/Volatility' />
            <PanelBlock title='Expert Analyses' />
            <PanelBlock title='News/Press' />
          </div>
        </HiddenElements>
        <div className='information'>
          <PanelBlock
            isUnauthorized={generalInfo.isUnauthorized}
            isLoading={generalInfo.isLoading || PriceQuery.loading}
            title='General Info'>
            <GeneralInfoBlock
              volume={!!PriceQuery.price && PriceQuery.price.volume}
              {...generalInfo.project} />
          </PanelBlock>
          <PanelBlock
            isUnauthorized={generalInfo.isUnauthorized}
            isLoading={generalInfo.isLoading}
            title='Financials'>
            <FinancialsBlock {...generalInfo.project} />
          </PanelBlock>
        </div>
      </FadeIn>
    </div>
  )
}

Detailed.propTypes = propTypes

const mapStateToProps = state => {
  return {
    projects: state.projects.items,
    loading: state.projects.isLoading
  }
}

const mapDispatchToProps = dispatch => {
  return {
    // TODO: have to retrive only selected project
    retrieveProjects: () => dispatch(retrieveProjects)
  }
}

const getPriceGQL = gql`
  query getPrice($ticker: String!) {
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
  query project($id: ID!) {
    project(
      id: $id,
    ){
      id,
      name,
      ticker,
      marketCapUsd,
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
      latestCoinmarketcapData {
        priceUsd,
        updateTime,
        marketCapUsd
      }
    }
  }
`

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

const mapPropsToOptions = ({match, projects}) => {
  const project = getProjectByTicker(match, projects)
  return {
    skip: !project,
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
  graphql(getPriceGQL, {
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
  lifecycle({
    componentDidMount () {
      this.props.retrieveProjects()
    }
  })
)

export default enhance(Detailed)
