import React from 'react'
import gql from 'graphql-tag'
import { graphql } from 'react-apollo'
import { compose } from 'recompose'
import ProjectCard from './Projects/ProjectCard'

const CashflowMobile = ({
  Projects: {
    projects = [],
    loading = true,
    isError = false,
    isEmpty = true
  }
}) => {
  return (
    <div style={{padding: 20}}>
      {projects.map((project, index) => (
        <ProjectCard key={index} {...project} />
      ))}
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
  const projects = allProjects.allProjects
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
  graphql(allProjectsGQL, {
    name: 'allProjects',
    props: mapDataToProps
  })
)

export default enhance(CashflowMobile)
