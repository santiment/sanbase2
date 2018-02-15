import React from 'react'
import { withRouter } from 'react-router-dom'
import { graphql } from 'react-apollo'
import * as qs from 'query-string'
import {
  compose,
  pure
} from 'recompose'
import { connect } from 'react-redux'
import 'font-awesome/css/font-awesome.css'
import logo from '../assets/logo_sanbase.png'
import AppMenu from './AppMenu'
import allProjectsGQL from './../pages/allProjectsGQL'
import AuthControl from './AuthControl'
import Search from './Search'
import './TopMenu.css'

export const TopMenu = ({
  user,
  loading,
  logout,
  history,
  location,
  projects
 }) => {
  const qsData = qs.parse(location.search)
  return (
    <div className='top-menu'>
      <div className='left'>
        <div
          onClick={() => history.push('/')}
          className='brand'>
          <img
            src={logo}
            width='115'
            height='22'
            alt='SANbase' />
        </div>
        <Search
          onSelectProject={ticker => history.push(`/projects/${ticker.toLowerCase()}`)}
          projects={projects} />
      </div>
      <div className='right'>
        <AppMenu
          showInsights={qsData && qsData.insights}
          handleNavigation={nextRoute => {
            history.push(`/${nextRoute}`)
          }} />
        <AuthControl
          login={() => history.push('/login')}
          openSettings={() => {
            history.push('/account')
          }}
          user={user}
          logout={logout} />
      </div>
    </div>
  )
}

const mapStateToProps = state => {
  return {
    user: state.user.data,
    loading: state.user.isLoading
  }
}

const mapDispatchToProps = dispatch => {
  return {
    logout: () => {
      dispatch({
        type: 'SUCCESS_LOGOUT'
      })
    }
  }
}

const mapDataToProps = ({allProjects, ownProps}) => {
  const projects = (allProjects.allProjects || [])
    .filter(project => {
      const defaultFilter = project.ethAddresses &&
        project.ethAddresses.length > 0 &&
        project.rank &&
        project.volumeUsd > 0
      return defaultFilter
    })

  return {
    projects
  }
}

const enhance = compose(
  connect(
    mapStateToProps,
    mapDispatchToProps
  ),
  withRouter,
  graphql(allProjectsGQL, {
    name: 'allProjects',
    props: mapDataToProps,
    options: () => {
      return {
        errorPolicy: 'all'
      }
    }
  }),
  pure
)

export default enhance(TopMenu)
