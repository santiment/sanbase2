import React from 'react'
import ReactTable from 'react-table'
import { connect } from 'react-redux'
import {
  compose,
  pure,
  lifecycle
} from 'recompose'
import 'react-table/react-table.css'
import moment from 'moment'
import { formatNumber } from './utils/formatting'

const formatDate = date => moment(date).format('YYYY-MM-DD')

const formatLastOutgoingWallet = wallets => {
  return wallets.map((wallet, index) => {
    const lastOutgoing = wallet.last_outgoing !== null
      ? formatDate(wallet.last_outgoing) : 'No recent transfers'
    return (
      <div key={index}>
        { lastOutgoing }
      </div>
    )
  })
}

const formatTxOutWallet = wallets => {
  return wallets.map((wallet, index) => {
    const txOut = wallet.tx_out || 0
    return (
      <div key={index}>
        {txOut.toLocaleString('en-US')}
      </div>
    )
  })
}

const formatBalanceWallet = ({wallets, ethPrice}) => {
  return wallets.map((wallet, index) => {
    const balance = wallet.balance || 0
    return (
      <div className='wallet' key={index}>
        <div className='usd first'>{formatNumber((balance * ethPrice), 'USD')}</div>
        <div className='eth'>
          <a className='address' href={'https://etherscan.io/address/' + wallet.address} target='_blank'>Ξ{ balance.toLocaleString('en-US') }
            <i className='fa fa-external-link' />
          </a>
        </div>
      </div>
    )
  })
}

const formatMarketCapProject = cap => {
  if (cap !== null) {
    return formatNumber(cap, 'USD')
  } else {
    return 'No data'
  }
}

const columns = [{
  Header: 'Project',
  id: 'project',
  filterable: true,
  sortable: true,
  accessor: d => ({
    name: d.name,
    ticker: d.ticker
  }),
  Cell: ({value}) => <div>{value.name} ({value.ticker})</div>,
  filterMethod: (filter, row) => {
    return row[filter.id].name.toLowerCase().indexOf(filter.value) !== -1 ||
      row[filter.id].ticker.toLowerCase().indexOf(filter.value) !== -1
  }
}, {
  Header: 'Market Cap',
  id: 'market_cap_usd',
  sortable: true,
  accessor: 'market_cap_usd',
  Cell: props => <span>{formatMarketCapProject(props.value)}</span>, // Custom cell components!
  sortMethod: (a, b) => {
    const _a = parseInt(a, 10)
    const _b = parseInt(b, 10)
    if (_a === _b) {
      return 0
    }
    return _a > _b ? 1 : -1
  }
}, {
  Header: 'Balance (USD/ETH)',
  id: 'balance',
  accessor: d => ({
    ethPrice: d.ethPrice,
    wallets: d.wallets
  }),
  Cell: props => <div>{formatBalanceWallet(props.value)}</div>
}, {
  Header: 'Last outgoing TX',
  id: 'tx',
  accessor: d => d.wallets,
  Cell: props => <div>{formatLastOutgoingWallet(props.value)}</div>
}, {
  Header: 'ETH sent',
  id: 'sent',
  accessor: d => d.wallets,
  Cell: props => <div>{formatTxOutWallet(props.value)}</div>
}]

export const Cashflow = ({
  projects,
  loading
}) => (
  <div>
    <h1>Cashflow</h1>
    <ReactTable
      loading={loading}
      showPagination={false}
      showPaginationTop={false}
      showPaginationBottom={false}
      sortable={false}
      resizable
      defaultSorted={[
        {
          id: 'market_cap_usd',
          desc: true
        }
      ]}
      className='-striped -highlight'
      data={projects}
      columns={columns}
    />
  </div>
)

const mapStateToProps = state => {
  return {
    projects: state.projects.items,
    loading: state.projects.loading
  }
}

const mapDispatchToProps = dispatch => {
  return {
    retrieveProjects: () => {
      dispatch({
        types: ['LOADING_PROJECTS', 'SUCCESS_PROJECTS', 'FAILED_PROJECTS'],
        payload: {
          client: 'sanbaseClient',
          request: {
            url: `/cashflow`
          }
        }
      })
    }
  }
}

const enhance = compose(
  connect(
    mapStateToProps,
    mapDispatchToProps
  ),
  lifecycle({
    componentDidMount () {
      this.props.retrieveProjects()
    }
  }),
  pure
)

export default enhance(Cashflow)
