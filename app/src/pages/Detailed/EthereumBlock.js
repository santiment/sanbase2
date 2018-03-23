import React from 'react'
import { graphql } from 'react-apollo'
import ReactTable from 'react-table'
import classnames from 'classnames'
import { withRouter } from 'react-router-dom'
import { compose } from 'recompose'
import { Loader } from 'semantic-ui-react'
import { simpleSort } from './../../utils/sortMethods'
import PanelBlock from './../../components/PanelBlock'
import { formatNumber } from '../../utils/formatting'
import { allShortProjectsGQL } from './../Projects/allProjectsGQL'
import { getProjects } from './../Projects/projectSelectors'
import { CustomThComponent, CustomHeadComponent } from './../Cashflow'
import { collectedField } from './FinancialsBlock'
import './../Cashflow.css'

const EthereumBlock = ({
  project = {},
  Projects = {
    allProjects: [],
    loading: true
  },
  loading = true,
  history
}) => {
  const projects = getProjects(Projects.allProjects)
  const columns = [{
    Header: 'Project',
    id: 'project',
    maxWidth: 210,
    filterable: true,
    sortable: true,
    accessor: d => ({
      name: d.name,
      ticker: d.ticker,
      cmcId: d.coinmarketcapId
    }),
    Cell: ({value}) => (
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
    Cell: ({value}) => <div>{
      value.map((wallet, index) => (
        <div key={index}>
          <a href={`https://etherscan.io/address/${wallet.address}`}>{wallet.address}</a>
        </div>
      ))
    }</div>,
    sortable: false
  }, {
    Header: 'ETH Collected',
    id: 'collected',
    maxWidth: 210,
    accessor: 'fundsRaisedIcos',
    Cell: ({value}) => <div>{
      value && value.map((amountIco, index) => {
        return <div key={index} >{
          collectedField(amountIco.currencyCode, amountIco.amount)
        }</div>
      })
    }</div>,
    sortable: false
  }, {
    Header: 'ETH spent (30D)',
    maxWidth: 110,
    id: 'tx',
    accessor: d => d.ethSpent,
    Cell: ({value}) => <div className='overview-ethspent'>{`Ξ${formatNumber(value)}`}</div>,
    sortable: true,
    sortMethod: (a, b) => simpleSort(a, b)
  }]
  return (
    <PanelBlock
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
  graphql(allShortProjectsGQL, {
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
