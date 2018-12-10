import React from 'react'
import { Link } from 'react-router-dom'
import { Icon, Popup } from 'semantic-ui-react'
import { simpleSort } from '../../utils/sortMethods'
import { formatNumber, millify } from '../../utils/formatting'
import ProjectIcon from '../../components/ProjectIcon'
import PercentChanges from '../../components/PercentChanges'

const columns = preload => [
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
    Header: 'Project',
    id: 'project',
    filterable: true,
    sortable: true,
    accessor: d => ({
      name: d.name,
      ticker: d.ticker,
      cmcId: d.coinmarketcapId
    }),
    Cell: ({ value }) => (
      <Link
        onMouseOver={preload}
        to={`/projects/${value.cmcId}`}
        className='overview-name'
      >
        {value.name}
      </Link>
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
    Header: 'Price',
    id: 'price',
    maxWidth: 100,
    accessor: d => ({
      priceUsd: d.priceUsd
    }),
    Cell: ({ value: { priceUsd, change24h } }) => (
      <div className='overview-price'>
        {priceUsd ? formatNumber(priceUsd, { currency: 'USD' }) : 'No data'}
      </div>
    ),
    sortable: true,
    sortMethod: (a, b) =>
      simpleSort(parseFloat(a.priceUsd || 0), parseFloat(b.priceUsd || 0))
  },
  {
    Header: 'Price +/-',
    id: 'price_change',
    maxWidth: 100,
    accessor: d => ({
      change24h: d.percentChange24h
    }),
    Cell: ({ value: { change24h } }) => (
      <div className='overview-price'>
        {change24h ? <PercentChanges changes={change24h} /> : 'No data'}
      </div>
    ),
    sortable: true,
    sortMethod: (a, b) =>
      simpleSort(parseFloat(a.change24h || 0), parseFloat(b.change24h || 0))
  },
  {
    Header: 'Volume',
    id: 'volume',
    maxWidth: 100,
    accessor: d => ({
      volumeUsd: d.volumeUsd
    }),
    Cell: ({ value: { volumeUsd } }) => (
      <div className='overview-volume'>
        {volumeUsd ? `$${millify(volumeUsd, 2)}` : 'No data'}
      </div>
    ),
    sortable: true,
    sortMethod: (a, b) =>
      simpleSort(parseFloat(a.volumeUsd || 0), parseFloat(b.volumeUsd || 0))
  },
  {
    Header: 'Volume +/-',
    id: 'volume_change_24h',
    maxWidth: 100,
    accessor: d => ({
      change24h: d.volumeChange24h
    }),
    Cell: ({ value: { change24h } }) => (
      <div className='overview-volume'>
        {change24h ? <PercentChanges changes={change24h} /> : 'No data'}
      </div>
    ),
    sortable: true,
    sortMethod: (a, b) =>
      simpleSort(parseFloat(a.change24h || 0), parseFloat(b.change24h || 0))
  },
  {
    Header: 'Market Cap',
    id: 'marketcapUsd',
    maxWidth: 130,
    accessor: 'marketcapUsd',
    Cell: ({ value }) => (
      <div className='overview-marketcap'>
        {value !== null ? `$${millify(value, 2)}` : 'No data'}
      </div>
    ),
    sortable: true,
    sortMethod: (a, b) => simpleSort(+a, +b)
  },
  {
    Header: 'ETH spent (30D)',
    maxWidth: 110,
    id: 'eth_spent',
    accessor: d => d.ethSpent,
    Cell: ({ value }) => (
      <div className='overview-ethspent'>{`Ξ${millify(value, 2)}`}</div>
    ),
    sortable: true,
    sortMethod: (a, b) => simpleSort(a, b)
  },
  {
    Header: 'Dev activity (30D)',
    id: 'github_activity',
    maxWidth: 110,
    accessor: d => d.averageGithubActivity,
    Cell: ({ value }) => (
      <div className='overview-devactivity'>
        {value ? parseFloat(value).toFixed(2) : ''}
      </div>
    ),
    sortable: true,
    sortMethod: (a, b) => simpleSort(a, b)
  },
  {
    Header: 'Daily active addresses (30D)',
    id: 'daily_active_addresses',
    maxWidth: 110,
    accessor: d => d.averageDailyActiveAddresses,
    Cell: ({ value }) => (
      <div className='overview-activeaddresses'>
        {value ? formatNumber(value) : ''}
      </div>
    ),
    sortable: true,
    sortMethod: (a, b) => simpleSort(a, b)
  },
  {
    Header: 'Signals',
    id: 'signals',
    minWidth: 64,
    accessor: d => ({
      warning: d.signals && d.signals.length > 0,
      description: d.signals[0] && d.signals[0].description
    }),
    Cell: ({ value: { warning, description } }) => (
      <div className='cell-signals'>
        {warning && (
          <Popup
            basic
            position='right center'
            hideOnScroll
            wide
            inverted
            trigger={
              <div style={{ width: '100%', height: '100%' }}>
                <Icon color='orange' fitted name='warning sign' />
              </div>
            }
            on='hover'
          >
            {description}
          </Popup>
        )}
      </div>
    ),
    sortable: true,
    sortMethod: (a, b) => simpleSort(a.warning, b.warning)
  }
]

export default columns
