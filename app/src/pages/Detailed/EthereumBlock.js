import React, { Fragment } from 'react'
import { graphql } from 'react-apollo'
import ReactTable from 'react-table'
import classnames from 'classnames'
import { withRouter } from 'react-router-dom'
import { compose } from 'recompose'
import { Loader } from 'semantic-ui-react'
import PanelBlock from './../../components/PanelBlock'
import { simpleSort } from './../../utils/sortMethods'
import { millify, getSymbolByCurrency } from '../../utils/formatting'
import { allErc20ShortProjectsGQL } from './../Projects/allProjectsGQL'
import { CustomThComponent, CustomHeadComponent } from './../Projects/ProjectsTable'
import './../Projects/ProjectsTable.css'
import './EthereumBlock.css'

const EthereumBlock = ({
  project = {},
  Projects = {
    allErc20Projects: [],
    loading: true
  },
  loading = true,
  history
}) => {
  const projects = Projects.allErc20Projects
  const columns = [{
    Header: 'Projects',
    id: 'project',
    maxWidth: 210,
    filterable: true,
    sortable: true,
    accessor: d => ({
      name: d.name,
      ticker: d.ticker,
      cmcId: d.coinmarketcapId
    }),
    Cell: ({value = {}}) => (
      <div
        onClick={() => history.push(`/projects/${value.cmcId}`)}
        className='overview-name' >
        {value.name}
      </div>
    ),
    filterMethod: (filter, row) => {
      const name = row[filter.id].name || ''
      const ticker = row[filter.id].ticker || ''
      return name.toLowerCase().indexOf(filter.value) !== -1 ||
        ticker.toLowerCase().indexOf(filter.value) !== -1
    }
  }, {
    Header: 'Wallets',
    id: 'wallets',
    accessor: 'ethAddresses',
    Cell: ({value = {}}) => <Fragment>{
      value.length > 0 ? value.map((wallet, index) => (
        <div key={index}
          className='wallet-addresses'>
          <a href={`https://etherscan.io/address/${wallet.address}`}>{wallet.address}</a>
        </div>
      )) : <div>
          No data
        </div>
    }</Fragment>,
    sortable: false
  }, {
    Header: 'Funds Collected',
    id: 'collected',
    maxWidth: 210,
    accessor: 'fundsRaisedIcos',
    Cell: ({value = {}}) => <Fragment>{
      value.length > 0 ? value.map((amountIco, index) => (
        <div className='ethereum-table-cell-funds-collected' key={index}>
          {`${getSymbolByCurrency(amountIco.currencyCode)}${millify(amountIco.amount, 2)}`}
        </div>
      )) : <div className='ethereum-table-cell-funds-collected'>
        No data
      </div>
    }</Fragment>,
    sortable: false
  }, {
    Header: 'ETH spent (30D)',
    maxWidth: 150,
    id: 'eth_spent',
    accessor: d => d.ethSpent,
    Cell: ({value}) => <div className='ethereum-table-cell-eth-spent'>{`Ξ${millify(value, 2)}`}</div>,
    sortable: true,
    sortMethod: (a, b) => simpleSort(a, b)
  }]
  return (
    <PanelBlock
      withDelimeter={false}
      isLoading={loading}
      title='Ethereum overview'>
      <ReactTable
        loading={loading}
        showPagination={false}
        showPaginationTop={false}
        showPaginationBottom={false}
        pageSize={projects && projects.length}
        sortable={false}
        resizable
        defaultSorted={[
          {
            id: 'marketcapUsd',
            desc: false
          }
        ]}
        className='-highlight'
        data={projects}
        columns={columns}
        LoadingComponent={({ className, loading, loadingText, ...rest }) => (
          <div
            className={classnames('-loading', { '-active': loading }, className)}
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

const enhance = compose(
  withRouter,
  graphql(allErc20ShortProjectsGQL, {
    name: 'Projects',
    options: () => {
      return {
        errorPolicy: 'all',
        notifyOnNetworkStatusChange: true
      }
    }
  })
)

export default enhance(EthereumBlock)
