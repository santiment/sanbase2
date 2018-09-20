import React from 'react'
import PanelBlock from './../../components/PanelBlock'
import moment from 'moment'
import { formatNumber } from './../../utils/formatting'
import ReactTable from 'react-table'
import SmoothDropdown from '../../components/SmoothDropdown/SmoothDropdown'
import SmoothDropdownItem from '../../components/SmoothDropdown/SmoothDropdownItem'

const DetailedEthTopTransactionsAddressCell = ({ value }) => (
  <SmoothDropdownItem
    trigger={
      <a
        // href={`https://etherscan.io/address/${value}`}
        // href={`#`}
        onMouseEnter={({ currentTarget }) => {
          // console.log(
          //   currentTarget.offsetWidth,
          //   currentTarget.parentNode.parentNode.offsetWidth
          // )
          if (
            currentTarget.offsetWidth + 10 <
            currentTarget.parentNode.parentNode.offsetWidth
          ) {
            // console.log(value)
          }
        }}
      >
        {value}
      </a>
    }
  >
    {value}
  </SmoothDropdownItem>
)

const COLUMNS = [
  {
    Header: 'Time',
    accessor: 'datetime'
  },
  {
    Header: 'Value',
    accessor: 'trxValue' // Required because our accessor is not a string
  },
  {
    Header: 'From',
    accessor: 'fromAddress', // String-based value accessors!
    Cell: DetailedEthTopTransactionsAddressCell
  },
  {
    Header: 'To',
    accessor: 'toAddress',
    Cell: DetailedEthTopTransactionsAddressCell
  }
]
/*

datetime
:
"2018-09-14T08:06:49.000000Z"
fromAddress
:
{address: "0x1f3df0b8390bb8e9e322972c5e75583e87608ec2", isExchange: false, __typename: "Address", Symbol(id): "$Project:101605.ethTopTransactions({"from":"2018-0…0:59:59Z","transactionType":"OUT"}).0.fromAddress"}
toAddress
:
{address: "0x55193c0fbf5921d4d91f26cc8cf84f5d72c6e50d", isExchange: false, __typename: "Address", Symbol(id): "$Project:101605.ethTopTransactions({"from":"2018-0…T20:59:59Z","transactionType":"OUT"}).0.toAddress"}
trxHash
:
"0x2bc7387aab0f3eac85abbb66ebf21323be2099281db8e852f82dd4e0d89cb0ce"
trxValue
:
350
*/

const DetailedEthTopTransactions = ({ Project }) => {
  const DATA = Project.project.ethTopTransactions.map(
    ({ trxValue, fromAddress, toAddress, datetime }) => ({
      trxValue,
      fromAddress: fromAddress.address,
      toAddress: toAddress.address,
      datetime: moment(datetime).format('YYYY-MM-DD HH:mm:ss')
    })
  )
  return (
    <PanelBlock isLoading={Project.loading} title='Top ETH Transactions'>
      <div>
        {console.log(Project)}
        {/* {Project.project.ethTopTransactions.map((transaction, index) => (
          <div className='top-eth-transaction' key={index}>
            <div className='top-eth-transaction__hash'>
              <a href={`https://etherscan.io/tx/${transaction.trxHash}`}>
                {transaction.trxHash}
              </a>
            </div>
            <div>
              {formatNumber(transaction.trxValue, 2)}
              &nbsp; | &nbsp;
              {moment(transaction.datetime).fromNow()}
            </div>
          </div>
        ))} */}
        <SmoothDropdown verticalMotion>
          <ReactTable
            data={DATA}
            columns={COLUMNS}
            showPagination={false}
            minRows={2}
          />
        </SmoothDropdown>
      </div>
    </PanelBlock>
  )
}

export default DetailedEthTopTransactions
