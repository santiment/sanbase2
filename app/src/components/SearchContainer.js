import React from 'react'
import { withRouter } from 'react-router-dom'
import { graphql } from 'react-apollo'
import { compose } from 'recompose'
import allProjectsGQL from './../pages/Projects/allProjectsGQL'
import Search from './Search'

const SearchContainer = ({
  history,
  projects = []
}) => {
  if (projects.length === 0) {
    return (
      <Search
        loading
        onSelectProject={() => {}}
        projects={[]}
      />
    )
  }
  return (
    <Search
      onSelectProject={ticker => history.push(`/projects/${ticker.toLowerCase()}`)}
      projects={projects} />
  )
}

const mapDataToProps = ({allProjects}) => {
  const projects = (allProjects.allProjects || [])
    .filter(project => {
      return project.ethAddresses &&
        project.ethAddresses.length > 0 &&
        project.rank &&
        project.volumeUsd > 0
    })
  return {
    projects
  }
}

const enhance = compose(
  withRouter,
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

export default enhance(SearchContainer)
