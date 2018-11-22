import { constructTotalMarketcapGQL } from './TotalMarketcapGQL'
import { getEscapedGQLFieldAlias } from '../../utils/utils'

const SLUGS = ['bitcoin', 'bitcoin-cash', 'ab-chain-rtb', '0x']
const ESCAPED_SLUGS = ['_bitcoin', '_bitcoincash', '_abchainrtb', '_0x']
const FROM_DATETIME = '2018-08-22T10:53:13Z'

describe('Total market cap widget queries', () => {
  it('should correctly escape slugs', () => {
    const escapedSlugs = SLUGS.map(getEscapedGQLFieldAlias)
    expect(escapedSlugs).toEqual(ESCAPED_SLUGS)
  })

  it('should correctly construct alias query', () => {
    const escapedSlugsMap = SLUGS.map(slug => [
      slug,
      getEscapedGQLFieldAlias(slug)
    ])

    const resultQQL = constructTotalMarketcapGQL(escapedSlugsMap, FROM_DATETIME)

    expect(resultQQL.loc.source.body).toMatchSnapshot()
  })
})
