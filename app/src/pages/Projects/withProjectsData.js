import { graphql } from 'react-apollo'
import { compose, withState, lifecycle } from 'recompose'
import {
  DEFAULT_SORT_BY,
  DEFAULT_FILTER_BY
} from './Filters'
import { allProjectsGQL, allErc20ProjectsGQL, currenciesGQL } from './allProjectsGQL'
import { simpleSort } from './../../utils/sortMethods'

const mapDataToProps = type => ({Projects, ownProps}) => {
  const loading = Projects.loading
  const isError = !!Projects.error
  const errorMessage = Projects.error ? Projects.error.message : ''
  const projects = Projects[pickProjects(type)] || []

  let filteredProjects = [...projects]
    .sort((a, b) => {
      if (ownProps.sortBy === 'github_activity') {
        return simpleSort(+a.averageDevActivity, +b.averageDevActivity)
      }
      return simpleSort(+a.marketcapUsd, +b.marketcapUsd)
    })
    .filter(project => {
      const hasSignals = project.signals && project.signals.length > 0
      const withSignals = ownProps.filterBy['signals']
      return withSignals ? hasSignals : true
    })
    .filter(project => {
      const hasSpentETH = project.ethSpent > 0
      const withSpentETH = ownProps.filterBy['spent_eth_30d']
      return withSpentETH ? hasSpentETH : true
    })

  if (ownProps.isSearchFocused && ownProps.filterName) {
    filteredProjects = filteredProjects.filter(project => {
      return project.name.toLowerCase().indexOf(ownProps.filterName) !== -1 ||
          project.ticker.toLowerCase().indexOf(ownProps.filterName) !== -1
    })
  }

  const isEmpty = projects.length === 0
  return {
    Projects: {
      loading,
      isEmpty,
      isError,
      projects,
      filteredProjects,
      errorMessage
    }
  }
}

const pickProjects = type => {
  switch (type) {
    case 'all':
      return 'allProjects'
    case 'currency':
      return 'allCurrencyProjects'
    case 'erc20':
      return 'allErc20Projects'
    default:
      return 'allProjects'
  }
}

const pickGQL = type => {
  switch (type) {
    case 'all':
      return allProjectsGQL
    case 'currency':
      return currenciesGQL
    case 'erc20':
      return allErc20ProjectsGQL
    default:
      return allProjectsGQL
  }
}

const enhance = (type = 'all') => compose(
  withState('isSearchFocused', 'focusSearch', false),
  withState('filterName', 'filterByName', null),
  withState('sortBy', 'changeSort', DEFAULT_SORT_BY),
  withState('filterBy', 'changeFilter', DEFAULT_FILTER_BY),
  withState('isFilterOpened', 'toggleFilter', false),
  graphql(pickGQL(type), {
    name: 'Projects',
    props: mapDataToProps(type),
    options: ({...props}) => {
      console.log(props)
      return {
        errorPolicy: 'all'
      }
    }
  }),
  lifecycle({
    componentDidUpdate (prevProps, prevState) {
      if (this.props.isSearchFocused !== prevProps.isSearchFocused) {
        const searchInput = document.querySelector('.search div input')
        searchInput && searchInput.focus()
      }
    }
  })
)

const withProjectsData = ({type = 'all'}) => WrappedComponent => {
  return enhance(type)(WrappedComponent)
}

export default withProjectsData
