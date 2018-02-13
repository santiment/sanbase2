import React from 'react'
import gql from 'graphql-tag'
import { graphql } from 'react-apollo'
import { SlideDown } from 'animate-components'
import { Loader, Message, Button } from 'semantic-ui-react'
import { compose, withState, lifecycle } from 'recompose'
import { ListView, ListViewItem } from './../components/ListView'
import ProjectCard from './Projects/ProjectCard'
import FloatingButton from './Projects/FloatingButton'
import { simpleSort } from './../utils/sortMethods'
import Search from './../components/Search'
import Filters from './Projects/Filters'
import './CashflowMobile.css'

const CashflowMobile = ({
  Projects = {
    projects: [],
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
  toggleFilter
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
  const filteredProjects = isSearchFocused && filterName
    ? projects.filter(project => {
      return project.name.toLowerCase().indexOf(filterName) !== -1 ||
          project.ticker.toLowerCase().indexOf(filterName) !== -1
    })
    : projects

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
        {filteredProjects.map((project, index) => (
          <ListViewItem height={500} key={index}>
            <div className='ListItem-project' >
              <ProjectCard
                onClick={() => history.push(`/projects/${project.ticker.toLowerCase()}`)}
                {...project} />
            </div>
          </ListViewItem>
        ))}
      </ListView>
      {isFilterOpened &&
        <Filters onFilterChanged={filters => {
          toggleFilter(!isFilterOpened)
          console.log(filters)
        }} />
      }
      <FloatingButton handleSearchClick={() => {
        filterByName(null)
        focusSearch(!isSearchFocused)
      }} />
    </div>
  )
}

const allProjectsGQL = gql`{
  allProjects {
    name
    rank
    description
    ticker
    marketSegment
    priceUsd
    percentChange24h
    volumeUsd
    volumeChange24h
    ethSpent
    averageDevActivity
    marketcapUsd
    ethBalance
    btcBalance
    ethAddresses {
      address
    }
    twitterData {
      followersCount
    }
    signals {
      name
      description
    }
  }
}`

const mapDataToProps = ({allProjects}) => {
  const loading = allProjects.loading
  const isError = !!allProjects.error
  const errorMessage = allProjects.error ? allProjects.error.message : ''
  const projects = (({projects = []}) => {
    return projects.filter(project => {
      const defaultFilter = project.ethAddresses &&
        project.ethAddresses.length > 0 &&
        project.rank
      return defaultFilter
    })
    .sort((a, b) => {
      return simpleSort(parseInt(a.marketcapUsd, 10), parseInt(b.marketcapUsd, 10))
    })
  })({
    projects: allProjects.allProjects
  })
  const isEmpty = projects.length === 0
  return {
    Projects: {
      loading,
      isEmpty,
      isError,
      projects,
      errorMessage
    }
  }
}

const enhance = compose(
  withState('isSearchFocused', 'focusSearch', false),
  withState('filterName', 'filterByName', null),
  withState('isFilterOpened', 'toggleFilter', false),
  lifecycle({
    componentDidUpdate (prevProps, prevState) {
      if (this.props.isSearchFocused !== prevProps.isSearchFocused) {
        const searchInput = document.querySelector('.search div input')
        searchInput && searchInput.focus()
      }
    }
  }),
  graphql(allProjectsGQL, {
    name: 'allProjects',
    props: mapDataToProps,
    options: () => {
      return {
        errorPolicy: 'all'
      }
    }
  })
)

export default enhance(CashflowMobile)
