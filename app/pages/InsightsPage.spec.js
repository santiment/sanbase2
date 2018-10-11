/* eslint-env jest */
import moment from 'moment'
import { sortByNewest, sortByPopular } from './InsightsPage'

const unsortedPosts = [
  {
    id: 1,
    title: 'check',
    link: 'https://asdfjhj.startrack',
    votes: {
      totalSanVotes: 0
    },
    createdAt: moment()
      .utc()
      .format()
  },
  {
    id: 2,
    title: 'check 2',
    link: 'https://asdfjhj.startrack',
    votes: {
      totalSanVotes: 3
    },
    createdAt: moment()
      .day(-1)
      .utc()
      .format()
  },
  {
    id: 3,
    title: 'check 3',
    link: 'https://asdfjhj.startrack',
    votes: {
      totalSanVotes: 1
    },
    createdAt: moment()
      .day(-5)
      .utc()
      .format()
  }
]

describe('sorts should work', () => {
  it('sortByNewest should return newest', () => {
    const sortedByNewestPosts = sortByNewest(unsortedPosts)
    expect(sortedByNewestPosts[0].id).toEqual(1)
  })

  it('sortByPopular should return popular', () => {
    const sortedByPopularPosts = sortByPopular(unsortedPosts)
    expect(sortedByPopularPosts[0].id).toEqual(2)
  })
})
