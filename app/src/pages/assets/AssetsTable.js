import React from 'react'
import ReactTable from 'react-table'
import cx from 'classnames'
import Sticky from 'react-stickynode'
import 'react-table/react-table.css'
import Panel from '../../components/Panel'
import ServerErrorMessage from './../../components/ServerErrorMessage'
import columns from './asset-columns'
import './../Projects/ProjectsTable.css'

export const CustomHeadComponent = ({ children, className, ...rest }) => (
  <Sticky enabled>
    <div className={cx('rt-thead', className)} {...rest}>
      {children}
    </div>
  </Sticky>
)

export const filterColumnsByTableSection = (tableSection, columns) => {
  if (tableSection === 'currencies') {
    return columns.filter(
      column =>
        column.id !== 'eth_spent' &&
        column.id !== 'daily_active_addresses' &&
        column.id !== 'signals'
    )
  }
  return columns
}

const AssetsTable = ({
  Assets = {
    items: [],
    isLoading: true,
    error: undefined,
    type: 'all'
  },
  showAll = false,
  goto,
  preload
}) => {
  const { isLoading, items, error, type } = Assets
  if (error && error.message !== 'Network error: Failed to fetch') {
    return <ServerErrorMessage />
  }

  return (
    <Panel className='assets-table-panel'>
      <ReactTable
        loading={isLoading}
        showPagination={!showAll}
        showPaginationTop={false}
        showPaginationBottom={true}
        defaultPageSize={20}
        pageSizeOptions={[5, 10, 20, 25, 50, 100]}
        pageSize={showAll ? items && items.length : undefined}
        sortable={false}
        resizable
        defaultSorted={[
          {
            id: 'marketcapUsd',
            desc: false
          }
        ]}
        className='-highlight'
        data={items}
        columns={filterColumnsByTableSection(type, columns(preload))}
        loadingText='Loading...'
        TheadComponent={CustomHeadComponent}
        getTdProps={(state, rowInfo, column, instance) => {
          return {
            onClick: (e, handleOriginal) => {
              if (handleOriginal) {
                handleOriginal()
              }
              if (rowInfo && rowInfo.original && rowInfo.original.ticker) {
                goto(`/projects/${rowInfo.original.coinmarketcapId}`)
              }
            }
          }
        }}
      />
    </Panel>
  )
}

export default AssetsTable
