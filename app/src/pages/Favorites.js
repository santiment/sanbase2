import React from 'react'
import { compose } from 'recompose'
import { graphql } from 'react-apollo'
import 'react-table/react-table.css'
import ProjectsTable from './Projects/ProjectsTable'
import withProjectsData from './Projects/withProjectsData'
import { followedProjectsGQL } from './../pages/Detailed/DetailedGQL'

export const Favorites = ({
  Projects,
  onSearch,
  handleSetCategory,
  history,
  match,
  search,
  tableInfo,
  categories,
  allMarketSegments,
  preload,
  user
}) => (
  <ProjectsTable
    Projects={Projects}
    onSearch={onSearch}
    handleSetCategory={handleSetCategory}
    history={history}
    match={match}
    search={search}
    tableInfo={tableInfo}
    categories={categories}
    allMarketSegments={allMarketSegments}
    preload={preload}
    user={user}
  />
)

export default compose(
  withProjectsData({ type: 'all' }),
  graphql(followedProjectsGQL, {
    name: 'FollowedProjects',
    props: ({ FollowedProjects, ownProps }) => {
      const { followedProjects = [] } = FollowedProjects
      const _followed = followedProjects.map(project => project.id)
      const { Projects = {} } = ownProps
      if (Projects.projects.length > 0 && _followed.length > 0) {
        return {
          Projects: {
            ...Projects,
            projects: Projects.projects.filter(project =>
              _followed.includes(project.id)
            )
          }
        }
      } else {
        return {
          Projects: {
            ...Projects,
            projects: []
          }
        }
      }
    }
  })
)(Favorites)
