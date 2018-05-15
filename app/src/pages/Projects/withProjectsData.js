import { graphql } from 'react-apollo'
import { connect } from 'react-redux'
import { withRouter } from 'react-router-dom'
import { compose, pure } from 'recompose'
import {
  allProjectsGQL,
  allErc20ProjectsGQL,
  currenciesGQL,
  allMarketSegmentsGQL
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
    onSearch: (event) => {
      dispatch({
        type: 'SET_SEARCH',
        payload: {
          search: event.target.value.toLowerCase()
        }
      })
    },
    handleSetCategory: (event) => {
      dispatch({
        type: 'SET_CATEGORY',
        payload: {
          category: event.target
        }
      })
    }
  }
}

const mapDataToProps = type => ({Projects}) => {
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
}

const pickProjectsType = type => {
  switch (type) {
    case 'all':
      return {
        projects: 'allProjects',
        gql: allProjectsGQL
      }
    case 'currency':
      return {
        projects: 'allCurrencyProjects',
        gql: currenciesGQL
      }
    case 'erc20':
      return {
        projects: 'allErc20Projects',
        gql: allErc20ProjectsGQL
      }
    default:
      return {
        projects: 'allProjects',
        gql: allProjectsGQL
      }
  }
}

const enhance = (type = 'all') => compose(
  connect(
    mapStateToProps,
    mapDispatchToProps
  ),
  withRouter,
  graphql(pickProjectsType(type).gql, {
    name: 'Projects',
    props: mapDataToProps(type),
    options: () => {
      return {
        errorPolicy: 'all',
        notifyOnNetworkStatusChange: true
      }
    }
  }),
  graphql(allMarketSegmentsGQL, {
    name: 'allMarketSegments',
    props: ({allMarketSegments: {allMarketSegments}}) => (
      { allMarketSegments: allMarketSegments ? JSON.parse(allMarketSegments) : {} }
    )
  }),
  pure
)

const withProjectsData = ({type = 'all'}) => WrappedComponent => {
  return enhance(type)(WrappedComponent)
}

export default withProjectsData
