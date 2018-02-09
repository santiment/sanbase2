import React from 'react'
import gql from 'graphql-tag'
import { graphql } from 'react-apollo'
import { SlideDown } from 'animate-components'
import { compose, withState, lifecycle } from 'recompose'
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
          <Search
            focus={focusSearch}
            onSelectProject={ticker => history.push(`/projects/${ticker.toLowerCase()}`)}
            projects={projects} />
        </SlideDown>}
      {projects.map((project, index) => (
        <ProjectCard key={index} {...project} />
      ))}
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
  const projects = allProjects.allProjects ? allProjects.allProjects.filter((_, index) => {
    return index < 10  // TODO: !
  }) : []
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
