import React, { Fragment } from 'react'
import ReactTable from 'react-table'
import classnames from 'classnames'
import { withRouter } from 'react-router-dom'
import { compose } from 'recompose'
import { Loader } from 'semantic-ui-react'
import PanelBlock from './PanelBlock'
import { simpleSort } from './../utils/sortMethods'
import { millify } from '../utils/formatting'
import ProjectIcon from './ProjectIcon'
import {
  CustomThComponent,
  CustomHeadComponent
} from './../pages/Projects/ProjectsTable'
import './../pages/Projects/ProjectsTable.css'
import './../pages/Detailed/EthereumBlock.css'
import './EthSpentTable.css'

const EthSpentTable = ({
  items = [],
  isLoading = true,
  error = 'undefined',
  type = 'all',
  showAll = false,
  history
}) => {
  const loading = isLoading
  const columns = [
    {
      Header: '',
      id: 'icon',
      filterable: true,
      sortable: true,
      minWidth: 44,
      maxWidth: 100,
      accessor: d => ({
        name: d.name,
        ticker: d.ticker
      }),
      Cell: ({ value }) => (
        <div className='overview-ticker'>
          <ProjectIcon name={value.name} ticker={value.ticker} />
          <br />
          <span className='ticker'>{value.ticker}</span>
        </div>
      )
    },
    {
      Header: 'Asset',
      id: 'project',
      maxWidth: 210,
      filterable: true,
      sortable: true,
      accessor: d => ({
        name: d.name,
        ticker: d.ticker,
        cmcId: d.coinmarketcapId
      }),
      Cell: ({ value = {} }) => (
        <div
          onClick={() => history.push(`/projects/${value.cmcId}`)}
          className='overview-name'
        >
          {value.name}
        </div>
      ),
      filterMethod: (filter, row) => {
        const name = row[filter.id].name || ''
        const ticker = row[filter.id].ticker || ''
        return (
          name.toLowerCase().indexOf(filter.value) !== -1 ||
          ticker.toLowerCase().indexOf(filter.value) !== -1
        )
      }
    },
    {
      Header: 'Funds Collected',
      id: 'collected-usd',
      maxWidth: 210,
      accessor: 'fundsRaisedUsdIcoEndPrice',
      Cell: ({ value }) =>
        value ? (
          <div className='ethereum-table-cell-eth-spent'>{`$${millify(
            value,
            2
          )}`}</div>
        ) : (
          <div>No data</div>
        ),
      sortable: true,
      sortMethod: (a, b) => simpleSort(+a, +b)
    },
    {
      Header: 'ETH spent (30D)',
      maxWidth: 150,
      id: 'eth_spent',
      accessor: d => d.ethSpent,
      Cell: ({ value }) => (
        <div className='ethereum-table-cell-eth-spent'>{`Ξ${millify(
          value,
          2
        )}`}</div>
      ),
      sortable: true,
      sortMethod: (a, b) => simpleSort(+a, +b)
    },
    {
      Header: 'ETH balance',
      maxWidth: 150,
      id: 'eth_balance',
      accessor: d => d.ethBalance,
      Cell: ({ value }) => (
        <div className='ethereum-table-cell-eth-spent'>{`Ξ${millify(
          value,
          2
        )}`}</div>
      ),
      sortable: true,
      sortMethod: (a, b) => simpleSort(+a, +b)
    },
    {
      Header: 'Wallets',
      id: 'wallets',
      accessor: 'ethAddresses',
      minWidth: 250,
      Cell: ({ value = {} }) => (
        <Fragment>
          {value.length > 0 ? (
            value.map((wallet, index) => (
              <div key={index} className='wallet-addresses'>
                <a href={`https://etherscan.io/address/${wallet.address}`}>
                  {wallet.address}
                </a>
              </div>
            ))
          ) : (
            <div>No data</div>
          )}
        </Fragment>
      ),
      sortable: false
    }
  ]
  return (
    <PanelBlock
      withDelimeter={false}
      isLoading={loading}
      title='Ethereum Spent Overview'
    >
      <ReactTable
        loading={loading}
        multiSort
        showPagination={!showAll}
        showPaginationTop={false}
        showPaginationBottom={true}
        pageSize={showAll ? items && items.length : undefined}
        sortable
        resizable
        defaultSorted={[
          {
            id: 'eth_balance',
            desc: false
          }
        ]}
        className='-highlight eth-spent-table'
        data={items}
        columns={columns}
        LoadingComponent={({ className, loading, loadingText, ...rest }) => (
          <div
            className={classnames(
              '-loading',
              { '-active': loading },
              className
            )}
            {...rest}
          >
            <div className='-loading-inner'>
              <Loader active size='large' />
            </div>
          </div>
        )}
        ThComponent={CustomThComponent}
        TheadComponent={CustomHeadComponent}
        getTdProps={(state, rowInfo, column, instance) => {
          return {
            onClick: (e, handleOriginal) => {
              if (handleOriginal) {
                handleOriginal()
              }
              if (rowInfo && rowInfo.original && rowInfo.original.ticker) {
                history.push(`/projects/${rowInfo.original.coinmarketcapId}`)
              }
            }
          }
        }}
      />
    </PanelBlock>
  )
}

const enhance = compose(withRouter)

export default enhance(EthSpentTable)
