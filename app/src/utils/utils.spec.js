/* eslint-env jest */
import moment from 'moment'
import {
  findIndexByDatetime,
  calculateBTCVolume,
  sanitizeMediumDraftHtml,
  filterProjectsByMarketSegment
} from './utils'

const labels = [
  moment('2018-01-15T06:00:00Z'),
  moment('2018-01-12T06:00:00Z'),
  moment('2018-01-11T18:00:00Z')
]

describe('findIndexByDatetime', () => {
  it('should return right index by datetime', () => {
    expect(findIndexByDatetime(labels, '2018-01-11T18:00:00Z')).toEqual(2)
  })

  it('should return -1, if labels array doesnt have datetime', () => {
    expect(findIndexByDatetime(labels, '2017-01-11T18:00:00Z')).toEqual(-1)
  })

  it('should return -1, if labels array is empty', () => {
    expect(findIndexByDatetime([], '2017-01-11T18:00:00Z')).toEqual(-1)
  })
})

const historyPrice = [
  {
    volume: '3313025',
    priceUsd: '2.2360575000000003',
    priceBtc: '0.00020811349999999999',
    marketcap: '72724491.75',
    datetime: '2017-11-29T09:00:00Z',
    __typename: 'PricePoint'
  },
  {
    volume: '9865673',
    priceUsd: '2.2590075',
    priceBtc: '0.00020983916666666665',
    marketcap: '73470907',
    datetime: '2017-11-29T10:00:00Z',
    __typename: 'PricePoint'
  },
  {
    volume: '9940505',
    priceUsd: '2.2839858333333334',
    priceBtc: '0.00021024283333333333',
    marketcap: '74283290.66666667',
    datetime: '2017-11-29T11:00:00Z',
    __typename: 'PricePoint'
  }
]

describe('calculateBTCVolume', () => {
  it('should return volume in BTC', () => {
    expect(calculateBTCVolume(historyPrice[0])).toEqual(308.34861283195977)
  })
})

describe('sanitizeMediumDraftHtml', () => {
  it('should sanitize script tags', () => {
    const dirty =
      '<html><body><p id="demo" /><script>document.getElementById("demo").innerHTML = "Hello JavaScript!";</script></body></html>'
    const clean = '<p id="demo"></p>'

    expect(sanitizeMediumDraftHtml(dirty)).toEqual(clean)
  })

  it('should sanitize scripts in event handlers', () => {
    const dirty =
      '<button onclick="myFunction()">Click me</button><p id="demo"></p><script>function myFunction() {document.getElementById("demo").innerHTML = "Hello World";}</script>'
    const clean = 'Click me<p id="demo"></p>'

    expect(sanitizeMediumDraftHtml(dirty)).toEqual(clean)
  })
})

describe('filterProjectsByMarketSegment', () => {
  it('should return expected values', () => {
    const allMarketSegments = {
      advertising: 'Advertising',
      blockchain_network: 'Blockchain Network',
      data: 'Data',
      digital_identity: 'Digital Identity',
      financial: 'Financial',
      gambling: 'Gambling',
      gaming: 'Gaming',
      legal: 'Legal',
      media: 'Media',
      prediction_market: 'Prediction Market',
      protocol: 'Protocol',
      transportation: 'Transportation',
      unknown: null
    }
    const dataProvider = [
      // projects is undefined, there is a category
      {
        projects: undefined,
        categories: { financial: true },
        expectation: undefined
      },
      // projects is an empty array, there is a category
      {
        projects: [],
        categories: { financial: true },
        expectation: []
      },
      // projects is an empty array, categories is an empty object
      {
        projects: [],
        categories: {},
        expectation: []
      },
      // projects is not empty, categories is an empty object
      {
        projects: [{ marketSegment: 'Financial' }],
        categories: {},
        expectation: [{ marketSegment: 'Financial' }]
      },
      // projects is not empty, there is a category
      {
        projects: [{ marketSegment: 'Financial' }, { marketSegment: 'media' }],
        categories: { financial: true },
        expectation: [{ marketSegment: 'Financial' }]
      },
      // projects is not empty, there are multiple categories
      {
        projects: [
          { marketSegment: 'Financial' },
          { marketSegment: 'Blockchain Network' },
          { marketSegment: 'Advertising' }
        ],
        categories: {
          financial: true,
          blockchain_network: true
        },
        expectation: [
          { marketSegment: 'Financial' },
          { marketSegment: 'Blockchain Network' }
        ]
      }
    ]
    dataProvider.map(data =>
      expect(
        filterProjectsByMarketSegment(
          data.projects,
          data.categories,
          allMarketSegments
        )
      ).toEqual(data.expectation)
    )
  })
})
