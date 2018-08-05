import React from 'react'
import ReactTable from 'react-table'
import cx from 'classnames'
import { Loader } from 'semantic-ui-react'
import Sticky from 'react-stickynode'
import 'react-table/react-table.css'
import Panel from '../../components/Panel'
import columns from './asset-columns'
import AssetsTableErrorMessage from './AssetsTableErrorMessage'
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
  goto,
  preload
}) => {
  const { isLoading, items, error, type } = Assets
  if (error && error.message !== 'Network error: Failed to fetch') {
    return <AssetsTableErrorMessage />
  }

  return (
    <Panel>
      <ReactTable
        loading={isLoading}
        showPagination={false}
        showPaginationTop={false}
        showPaginationBottom={false}
        pageSize={items && items.length}
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
        LoadingComponent={({ className, loading, loadingText, ...rest }) => (
          <div
            className={cx('-loading', { '-active': loading }, className)}
            {...rest}
          >
            <div className='-loading-inner'>
              <Loader active size='large' />
            </div>
          </div>
        )}
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
