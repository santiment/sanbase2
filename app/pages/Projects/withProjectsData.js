import { graphql } from 'react-apollo'
import { connect } from 'react-redux'
import { withRouter } from 'react-router-dom'
import { compose, pure } from 'recompose'
import {
  allProjectsGQL,
  allErc20ProjectsGQL,
  currenciesGQL,
  allMarketSegmentsGQL,
  currenciesMarketSegmentsGQL,
  erc20MarketSegmentsGQL
} from './allProjectsGQL'

const mapStateToProps = state => {
  return {
    search: state.projects.search,
    tableInfo: state.projects.tableInfo,
    categories: state.projects.categories,
    user: state.user
  }
}

const mapDispatchToProps = dispatch => {
  return {
    onSearch: event => {
      dispatch({
        type: 'SET_SEARCH',
        payload: {
          search: event.target.value.toLowerCase()
        }
      })
    },
    handleSetCategory: event => {
      dispatch({
        type: 'SET_CATEGORY',
        payload: {
          category: event.target
        }
      })
    }
  }
}

const mapDataToProps = type => {
  return {
    projects: ({ Projects }) => {
      const loading = Projects.loading
      const isError = !!Projects.error
      const errorMessage = Projects.error ? Projects.error.message : ''
      const projects = Projects[pickProjectsType(type).projects] || []

      const isEmpty = projects && projects.length === 0
      return {
        Projects: {
          loading,
          isEmpty,
          isError,
          projects,
          errorMessage,
          refetch: Projects.refetch
        }
      }
    },
    marketSegments: ({ marketSegments }) => {
      marketSegments =
        marketSegments[pickProjectsType(type).marketSegments] || []
      return { marketSegments }
    }
  }
}

const pickProjectsType = type => {
  switch (type) {
    case 'all':
      return {
        projects: 'allProjects',
        projectsGQL: allProjectsGQL,
        marketSegments: 'allMarketSegments',
        marketSegmentsGQL: allMarketSegmentsGQL
      }
    case 'currency':
      return {
        projects: 'allCurrencyProjects',
        projectsGQL: currenciesGQL,
        marketSegments: 'currenciesMarketSegments',
        marketSegmentsGQL: currenciesMarketSegmentsGQL
      }
    case 'erc20':
      return {
        projects: 'allErc20Projects',
        projectsGQL: allErc20ProjectsGQL,
        marketSegments: 'erc20MarketSegments',
        marketSegmentsGQL: erc20MarketSegmentsGQL
      }
    default:
      return {
        projects: 'allProjects',
        projectsGQL: allProjectsGQL,
        marketSegments: 'allMarketSegments',
        marketSegmentsGQL: allMarketSegmentsGQL
      }
  }
}

const enhance = (type = 'all') =>
  compose(
    connect(
      mapStateToProps,
      mapDispatchToProps
    ),
    withRouter,
    graphql(pickProjectsType(type).projectsGQL, {
      name: 'Projects',
      props: mapDataToProps(type).projects,
      options: () => {
        return {
          errorPolicy: 'all',
          notifyOnNetworkStatusChange: true
        }
      }
    }),
    graphql(pickProjectsType(type).marketSegmentsGQL, {
      name: 'marketSegments',
      props: mapDataToProps(type).marketSegments
    }),
    pure
  )

const withProjectsData = ({ type = 'all' }) => WrappedComponent => {
  return enhance(type)(WrappedComponent)
}

export default withProjectsData
