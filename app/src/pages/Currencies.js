import React from 'react'
import 'react-table/react-table.css'
import ProjectsTabel from 'pages/Projects/ProjectsTabel'
import withProjectsData from 'pages/Projects/withProjectsData'

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
  <ProjectsTabel
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

export default withProjectsData({type: 'currency'})(Currencies)
