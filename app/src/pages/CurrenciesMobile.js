import React from 'react'
import { graphql } from 'react-apollo'
import { compose, withState, lifecycle } from 'recompose'

import { simpleSort } from './../utils/sortMethods'
import ProjectsMobile from './Projects/ProjectsMobile'
import {
  DEFAULT_SORT_BY,
  DEFAULT_FILTER_BY
} from './Projects/Filters'
import allProjectsGQL from './Projects/allProjectsGQL'

const CurrenciesMobile = (props) => <ProjectsMobile {...props} />

const mapDataToProps = ({allProjects, ownProps}) => {
  const loading = allProjects.loading
  const isError = !!allProjects.error
  const errorMessage = allProjects.error ? allProjects.error.message : ''
  const projects = allProjects.allProjects || []

  let filteredProjects = [...projects]
    .sort((a, b) => {
      if (ownProps.sortBy === 'github_activity') {
        return simpleSort(
          parseInt(a.averageDevActivity, 10),
          parseInt(b.averageDevActivity, 10)
        )
      }
      return simpleSort(
        parseInt(a.marketcapUsd, 10),
        parseInt(b.marketcapUsd, 10)
      )
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

const enhance = compose(
  withState('isSearchFocused', 'focusSearch', false),
  withState('filterName', 'filterByName', null),
  withState('sortBy', 'changeSort', DEFAULT_SORT_BY),
  withState('filterBy', 'changeFilter', DEFAULT_FILTER_BY),
  withState('isFilterOpened', 'toggleFilter', false),
  graphql(allProjectsGQL, {
    name: 'allProjects',
    props: mapDataToProps,
    options: () => {
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

export default enhance(CurrenciesMobile)
