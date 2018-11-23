import { constructTotalMarketcapGQL } from './TotalMarketcapGQL'
import { getEscapedGQLFieldAlias } from '../../utils/utils'

const SLUGS = ['bitcoin', 'bitcoin-cash', 'ab-chain-rtb', '0x']
const FROM_DATETIME = '2018-08-22T10:53:13Z'

describe('Total market cap widget queries', () => {
  it('should correctly construct alias query', () => {
    const escapedSlugsMap = SLUGS.map(slug => [
      slug,
      getEscapedGQLFieldAlias(slug)
    ])

    const resultQQL = constructTotalMarketcapGQL(escapedSlugsMap, FROM_DATETIME)

    expect(resultQQL.loc.source.body).toMatchSnapshot()
  })
})
