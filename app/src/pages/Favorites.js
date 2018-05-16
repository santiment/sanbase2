import React from 'react'
import 'react-table/react-table.css'
import ProjectsTable from './Projects/ProjectsTable'
import withProjectsData from './Projects/withProjectsData'

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
}) => {
  if (Projects.projects.length > 0 &&
    user.followedProjects && user.followedProjects.length > 0) {
    Projects = {
      ...Projects,
      projects: Projects.projects.filter((project) => user.followedProjects.includes(project.id))
    }
  } else {
    Projects = {
      ...Projects,
      projects: []
    }
  }

  return (
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
}

export default withProjectsData({type: 'all'})(Favorites)
