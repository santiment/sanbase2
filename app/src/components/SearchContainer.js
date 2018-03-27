import React from 'react'
import { withRouter } from 'react-router-dom'
import { graphql } from 'react-apollo'
import { compose } from 'recompose'
import allProjectsGQL from './../pages/Projects/allProjectsGQL'
import { getAll } from './../pages/Projects/projectSelectors'
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
      onSelectProject={cmcId => history.push(`/projects/${cmcId}`)}
      projects={projects} />
  )
}

const mapDataToProps = ({allProjects}) => ({
  projects: getAll(allProjects.allProjects)
})

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
