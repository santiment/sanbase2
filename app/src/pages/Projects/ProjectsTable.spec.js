/* eslint-env jest */
import { filterColumnsByTableSection } from './ProjectsTable'

const columns = [
  {
    id: 'project'
  },
  {
    id: 'daily_active_addresses'
  },
  {
    id: 'eth_spent'
  }
]

describe('filterColumnsByTableSection', () => {
  it('should return columns for erc20 projects', () => {
    const newColumns = filterColumnsByTableSection('projects', columns)
    expect(newColumns.length).toEqual(3)
  })

  it('should return columns for currencies', () => {
    const newColumns = filterColumnsByTableSection('currencies', columns)
    expect(newColumns.length).toEqual(1)
  })
})
