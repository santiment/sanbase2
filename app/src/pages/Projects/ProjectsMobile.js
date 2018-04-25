import React from 'react'
import { SlideDown } from 'animate-components'
import { Loader, Message, Button } from 'semantic-ui-react'
import { List, AutoSizer } from 'react-virtualized'

import Search from './../../components/Search'
import ProjectCard from './ProjectCard'
import FloatingButton from './FloatingButton'
import Filters, {
  DEFAULT_SORT_BY,
  DEFAULT_FILTER_BY
} from './Filters'
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
  sortBy = DEFAULT_SORT_BY,
  type = 'erc20'
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

  const rowRenderer = ({
    key,
    index,
    isScrolling,
    isVisible,
    style
  }) => {
    const project = Projects.filteredProjects[index]

    return (
      <div
        key={key}
        style={style}
      >
        <ProjectCard
          type={type}
          onClick={() => history.push(`/projects/${project.coinmarketcapId}`)}
          {...project}
        />
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
      <div className='List'>
        <AutoSizer>
          {({ height, width }) => (
            <List
              width={width}
              height={height}
              rowCount={Projects.filteredProjects.length}
              rowHeight={type === 'erc20' ? 470 : 400}
              rowRenderer={rowRenderer}
            />
          )}
        </AutoSizer>
      </div>
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
