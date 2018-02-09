import React from 'react'
import gql from 'graphql-tag'
import { graphql } from 'react-apollo'
import { SlideDown } from 'animate-components'
import { compose, withState, lifecycle } from 'recompose'
import { ListView, ListViewItem } from './../components/ListView'
import ProjectCard from './Projects/ProjectCard'
import FloatingButton from './Projects/FloatingButton'
import Search from './../components/Search'
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
  focusSearch
}) => {
  const { projects = [] } = Projects
  return (
    <div className='cashflow-mobile'>
      {isSearchFocused &&
        <SlideDown duration='0.3s' timingFunction='ease-out' as='div'>
          <div className='cashflow-mobile-search'>
            <Search
              focus={focusSearch}
              onSelectProject={ticker => history.push(`/projects/${ticker.toLowerCase()}`)}
              projects={projects} />
          </div>
        </SlideDown>}
      <ListView
        style={{
          top: isSearchFocused ? 60 : 0
        }}
        runwayItems={7}
        runwayItemsOpposite={5}
        aveCellHeight={420}
      >
        {projects.map((project, index) => (
          <ListViewItem height={420} key={index}>
            <div className='ListItem-project' >
              <ProjectCard {...project} />
            </div>
          </ListViewItem>
        ))}
      </ListView>
      <FloatingButton handleSearchClick={() => focusSearch(!isSearchFocused)} />
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
  }
}`

const mapDataToProps = ({allProjects}) => {
  const loading = allProjects.loading
  const isEmpty = !!allProjects.project
  const isError = !!allProjects.error
  const errorMessage = allProjects.error ? allProjects.error.message : ''
  const projects = allProjects.allProjects || []
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
    props: mapDataToProps
  })
)

export default enhance(CashflowMobile)
