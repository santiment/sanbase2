import React from 'react'
import 'react-table/react-table.css'
import ProjectsTable from 'pages/Projects/ProjectsTable'
import withProjectsData from 'pages/Projects/withProjectsData'

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
  if (Projects.projects.length > 0 && user.followedProjects.length > 0) {
    Projects = {
      ...Projects,
      projects: Projects.projects.filter((project) => user.followedProjects.includes(project.id))
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
