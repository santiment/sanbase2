import React from 'react'
import PropTypes from 'prop-types'
import { connect } from 'react-redux'
import {
  compose,
  pure,
  lifecycle
} from 'recompose'
import { Redirect } from 'react-router-dom'
import { Tab, Tabs, TabList, TabPanel } from 'react-tabs'
import ProjectIcon from './../components/ProjectIcon'
import PanelBlock from './../components/PanelBlock'
import { retrieveProjects } from './Cashflow.actions.js'
import './Detailed.css'

const propTypes = {
  match: PropTypes.object.isRequired,
  projects: PropTypes.array.isRequired,
  loading: PropTypes.bool.isRequired
}

export const Detailed = ({match, projects, loading}) => {
  if (loading) {
    return (
      <div className='page detailed'>
        <h2>Loading...</h2>
      </div>
    )
  }
  const selectedTicker = match.params.ticker
  const project = projects.find(el => {
    const ticker = el.ticker || ''
    return ticker.toLowerCase() === selectedTicker
  })
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
        <div className='detailed-buttons'>
          <a href='#' className='add-to-dashboard'>
            <i className='fa fa-plus' />
            &nbsp; Add to Dashboard
          </a>
        </div>
      </div>
      <div className='panel'>
        <Tabs className='main-chart'>
          <TabList className='nav'>
            <Tab className='nav-item' selectedClassName='active'>
              <a className='nav-link' href='#'>
                $2.29 USD (not real) &nbsp;
                <span className='diff down'>
                  <i className='fa fa-caret-down' />
                    &nbsp; 8.87% (not real)
                </span>
              </a>
            </Tab>
            <Tab className='nav-item' selectedClassName='active'>
              <a className='nav-link' href='#'>
                2.29 BTC (not real) &nbsp;
                <span className='diff up'>
                  <i className='fa fa-caret-up' />
                    &nbsp; 8.87% (not real)
                </span>
              </a>
            </Tab>
          </TabList>
          <TabPanel>
            1
          </TabPanel>
          <TabPanel>
            2
          </TabPanel>
        </Tabs>
      </div>
      <div className='panel'>
        <Tabs className='activity-panel'>
          <TabList className='nav'>
            <Tab className='nav-item' selectedClassName='active'>
              <a className='nav-link' href='#'>
                Social Mentions
              </a>
            </Tab>
            <Tab className='nav-item' selectedClassName='active'>
              <a className='nav-link' href='#'>
                Social Activity over Time
              </a>
            </Tab>
            <Tab className='nav-item' selectedClassName='active'>
              <a className='nav-link' href='#'>
                Sentiment/Intensity
              </a>
            </Tab>
            <Tab className='nav-item' selectedClassName='active'>
              <a className='nav-link' href='#'>
                Github Activity
              </a>
            </Tab>
            <Tab className='nav-item' selectedClassName='active'>
              <a className='nav-link' href='#'>
                SAN Community
              </a>
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
      <div className='row analysis'>
        <PanelBlock title='Signals/Volatility' />
        <PanelBlock title='Expert Analyses' />
        <PanelBlock title='News/Press' />
      </div>
      <div className='row information'>
        <PanelBlock title='General Info' />
        <PanelBlock title='Financials' />
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
  pure
)

export default enhance(Detailed)
