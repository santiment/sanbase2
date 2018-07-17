import React from 'react'
import 'react-table/react-table.css'
import ProjectsTable from './Projects/ProjectsTable'
import withProjectsData from './Projects/withProjectsData'

export const Currencies = ({
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

export default withProjectsData({ type: 'currency' })(Currencies)
