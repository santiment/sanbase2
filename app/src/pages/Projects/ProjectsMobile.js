import React from 'react'
import { SlideDown } from 'animate-components'
import { Loader, Message, Button } from 'semantic-ui-react'

import { ListView, ListViewItem } from 'components/ListView'
import ProjectCard from 'pages/Projects/ProjectCard'
import FloatingButton from 'pages/Projects/FloatingButton'
import Search from 'components/Search'
import Filters, {
  DEFAULT_SORT_BY,
  DEFAULT_FILTER_BY
} from 'pages/Projects/Filters'
import './ProjectsMobile.css'

const ProjectsMobile = ({
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

export default ProjectsMobile
