import React from 'react'
import { graphql } from 'react-apollo'
import { SlideDown } from 'animate-components'
import { Loader, Message, Button } from 'semantic-ui-react'
import { compose, withState, lifecycle } from 'recompose'
import { ListView, ListViewItem } from './../components/ListView'
import ProjectCard from './Projects/ProjectCard'
import FloatingButton from './Projects/FloatingButton'
import { simpleSort } from 'utils/sortMethods'
import Search from './../components/Search'
import Filters, {
  DEFAULT_SORT_BY,
  DEFAULT_FILTER_BY
} from './Projects/Filters'
import { allErc20ProjectsGQL } from './Projects/allProjectsGQL'
import './CashflowMobile.css'

const CashflowMobile = ({
  Projects = {
    projects: [],
    filteredProjects: [],
    loading: true,
    isError: false,
    isEmpty: true
  },
  history,
  isSearchFocused = false,
  focusSearch,
  filterName = null,
  filterByName,
  isFilterOpened = false,
  toggleFilter,
  changeFilter,
  changeSort,
  filterBy = DEFAULT_FILTER_BY,
  sortBy = DEFAULT_SORT_BY
}) => {
  const { projects = [] } = Projects
  if (Projects.loading) {
    return (<Loader active size='large' />)
  }
  if (Projects.isError) {
    return (
      <div style={{display: 'flex', alignItems: 'center', justifyContent: 'center', height: '80vh'}}>
        <Message warning>
          <Message.Header>Something going wrong on our server.</Message.Header>
          <p>Please try again later.</p>
        </Message>
      </div>
    )
  }

  return (
    <div className='cashflow-mobile'>
      {isSearchFocused &&
        <SlideDown duration='0.3s' timingFunction='ease-out' as='div'>
          <div className='cashflow-mobile-search'>
            <Search
              focus={focusSearch}
              onSelectProject={ticker => filterByName(ticker.toLowerCase())}
              projects={projects} />
            <Button
              basic
              onClick={() => toggleFilter(!isFilterOpened)}
              className='cashflow-mobile-search__filter'>
              Filter
            </Button>
          </div>
        </SlideDown>}
      <ListView
        style={{
          top: isSearchFocused ? 60 : 0
        }}
        runwayItems={7}
        runwayItemsOpposite={5}
        aveCellHeight={460}
      >
        {Projects.filteredProjects.map((project, index) => (
          <ListViewItem height={500} key={index}>
            <div className='ListItem-project' >
              <ProjectCard
                onClick={() => history.push(`/projects/${project.coinmarketcapId}`)}
                {...project} />
            </div>
          </ListViewItem>
        ))}
      </ListView>
      {isFilterOpened &&
        <Filters
          filterBy={filterBy}
          sortBy={sortBy}
          changeFilter={changeFilter}
          changeSort={changeSort}
          onFilterChanged={filters => {
            toggleFilter(!isFilterOpened)
          }} />
      }
      <FloatingButton handleSearchClick={() => {
        filterByName(null)
        focusSearch(!isSearchFocused)
      }} />
    </div>
  )
}

const mapDataToProps = ({allProjects, ownProps}) => {
  const loading = allProjects.loading
  const isError = !!allProjects.error
  const errorMessage = allProjects.error ? allProjects.error.message : ''
  const projects = allProjects.allProjects

  let filteredProjects = projects
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
  graphql(allErc20ProjectsGQL, {
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

export default enhance(CashflowMobile)
