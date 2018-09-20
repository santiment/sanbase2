import React, { Fragment } from 'react'
import { Label } from 'semantic-ui-react'
import PanelBlock from './../../components/PanelBlock'
import moment from 'moment'
import { formatNumber } from './../../utils/formatting'
import ReactTable from 'react-table'
import SmoothDropdown from '../../components/SmoothDropdown/SmoothDropdown'
import SmoothDropdownItem from '../../components/SmoothDropdown/SmoothDropdownItem'
import './DetailedEthTopTransactions.css'

const getAddressMarkup = ({ address, isExchange }) => (
  <Fragment>
    {isExchange ? <Label color='yellow'>exchange</Label> : null}
    <a href={`https://etherscan.io/address/${address}`}>{address}</a>
  </Fragment>
)

const DetailedEthTopTransactionsAddressCell = ({ value }) => (
  <SmoothDropdownItem
    showIf={({ currentTarget: trigger }) =>
      trigger.offsetWidth + 10 >= trigger.parentNode.offsetWidth
    }
    trigger={getAddressMarkup(value)}
  >
    {value.address}
  </SmoothDropdownItem>
)

const COLUMNS = [
  {
    Header: 'Time',
    accessor: 'datetime',
    sortMethod: (a, b) => {
      return moment(a).isAfter(moment(b)) ? 1 : -1
    }
  },
  {
    Header: 'Value',
    accessor: 'trxValue',
    sortMethod: (a, b) => {
      return parseFloat(a) > parseFloat(b) ? 1 : -1
    }
  },
  {
    Header: 'From',
    accessor: 'fromAddress',
    Cell: DetailedEthTopTransactionsAddressCell,
    sortable: false
  },
  {
    Header: 'To',
    accessor: 'toAddress',
    Cell: DetailedEthTopTransactionsAddressCell,
    sortable: false
  }
]

const DetailedEthTopTransactions = ({ Project }) => {
  const DATA = Project.project.tokenTopTransactions
    .slice(0, 10)
    .map(({ trxValue, fromAddress, toAddress, datetime }) => ({
      trxValue: formatNumber(trxValue),
      fromAddress: fromAddress,
      toAddress: toAddress,
      datetime: moment(datetime).format('YYYY-MM-DD HH:mm:ss')
    }))
  return (
    <PanelBlock isLoading={Project.loading} title='Top ETH Transactions'>
      <SmoothDropdown verticalMotion>
        <ReactTable
          data={DATA}
          columns={COLUMNS}
          showPagination={false}
          minRows={2}
          className='DetailedEthTopTransactions'
        />
      </SmoothDropdown>
    </PanelBlock>
  )
}

export default DetailedEthTopTransactions
