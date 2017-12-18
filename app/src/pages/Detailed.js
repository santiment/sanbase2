import React from 'react'
import PropTypes from 'prop-types'
import { connect } from 'react-redux'
import { graphql } from 'react-apollo'
import gql from 'graphql-tag'
import {
  compose,
  pure,
  lifecycle
} from 'recompose'
import { Merge } from 'animate-components'
import { fadeIn, slideRight } from 'animate-keyframes'
import { Redirect } from 'react-router-dom'
import { Tab, Tabs, TabList, TabPanel } from 'react-tabs'
import ProjectIcon from './../components/ProjectIcon'
import PanelBlock from './../components/PanelBlock'
import { retrieveProjects } from './Cashflow.actions.js'
import GeneralInfoBlock from './../components/GeneralInfoBlock'
import FinancialsBlock from './../components/FinancialsBlock'
import ProjectChart from './ProjectChart'
import { formatNumber, formatBTC } from '../utils/formatting'
import './Detailed.css'

const propTypes = {
  match: PropTypes.object.isRequired,
  projects: PropTypes.array.isRequired,
  loading: PropTypes.bool.isRequired
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
  price
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
        {!price.loading && price.price &&
          <Merge
            one={{ name: fadeIn, duration: '0.3s', timingFunction: 'ease-in' }}
            two={{ name: slideRight, duration: '0.5s', timingFunction: 'ease-out' }}
            as='div'
          >
            <div className='detailed-price'>
              <div>{formatNumber(price.price.priceUsd, 'USD')}</div>
              <div>BTC {formatBTC(parseFloat(price.price.priceBtc))}</div>
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
      <div className='panel'>
        <ProjectChart ticker={project.ticker.toUpperCase()} />
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
        <PanelBlock title='Blockchain Analytics' />
        <div className='analysis'>
          <PanelBlock title='Signals/Volatility' />
          <PanelBlock title='Expert Analyses' />
          <PanelBlock title='News/Press' />
        </div>
        <div className='information'>
          <PanelBlock title='General Info'>
            <GeneralInfoBlock info={project} />
          </PanelBlock>
          <PanelBlock title='Financials'>
            <FinancialsBlock info={project} />
          </PanelBlock>
        </div>
      </HiddenElements>
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
      datetime
    }
}`

const enhance = compose(
  connect(
    mapStateToProps,
    mapDispatchToProps
  ),
  lifecycle({
    componentDidMount () {
      this.props.retrieveProjects()
    }
  }),
  graphql(getPriceGQL, {
    name: 'price',
    options: ({match, projects}) => {
      const project = getProjectByTicker(match, projects)
      return {
        variables: {
          'ticker': project ? project.ticker.toUpperCase() : 'SAN'
        }
      }
    }
  }),
  pure
)

export default enhance(Detailed)
