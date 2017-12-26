import React from 'react'
import PropTypes from 'prop-types'
import { connect } from 'react-redux'
import {
  compose,
  lifecycle
} from 'recompose'
import { Redirect } from 'react-router-dom'
import { Tab, Tabs, TabList, TabPanel } from 'react-tabs'
import gql from 'graphql-tag'
import { graphql } from 'react-apollo'
import { retrieveProjects } from './Cashflow.actions.js'
import ProjectIcon from './../components/ProjectIcon'
import PanelBlock from './../components/PanelBlock'
import GeneralInfoBlock from './../components/GeneralInfoBlock'
import FinancialsBlock from './../components/FinancialsBlock'
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
      <div className='detailed-head'>
        <div className='detailed-name'>
          <h1><ProjectIcon name={project.name} size={28} /> {project.name} ({project.ticker.toUpperCase()})</h1>
          <p>Manage entire organisations using the blockchain.</p>
        </div>
        <HiddenElements>
          <div className='detailed-buttons'>
            <button className='add-to-dashboard'>
              <i className='fa fa-plus' />
              &nbsp; Add to Dashboard
            </button>
          </div>
        </HiddenElements>
      </div>
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
          isLoading={generalInfo.isLoading}
          title='General Info'>
          <GeneralInfoBlock {...generalInfo.project} />
        </PanelBlock>
        <PanelBlock
          isUnauthorized={generalInfo.isUnauthorized}
          isLoading={generalInfo.isLoading}
          title='Financials'>
          <FinancialsBlock {...generalInfo.project} />
        </PanelBlock>
      </div>
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

const mapDataToProps = ({data}) => {
  const isLoading = data.loading
  const isEmpty = !!data.project
  const isError = !!data.error
  const errorMessage = data.error ? data.error.message : ''
  const isUnauthorized = data.error ? /\bunauthorized/.test(data.error.message) : false
  if (data.error && !isUnauthorized) {
    // If our API server is not reponed with data
    throw new Error(data.error.message)
  }
  const project = data.project

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
  graphql(queryProject, {
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
