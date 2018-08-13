import { hasAssetById } from './Watchlists'

describe('hasListItemsThisAssetById', () => {
  it('should return false if we dont have item in the list', () => {
    expect(
      hasAssetById({
        listItems: [],
        id: '736'
      })
    ).toEqual(false)
  })

  it('should return true if we have item in the list', () => {
    expect(
      hasAssetById({
        listItems: [
          {
            project: { id: '736', __typename: 'Project' },
            __typename: 'ListItem'
          }
        ],
        id: '736'
      })
    ).toEqual(true)

    expect(
      hasAssetById({
        listItems: [
          {
            project: { id: '736', __typename: 'Project' },
            __typename: 'ListItem'
          },
          {
            project: { id: '716', __typename: 'Project' },
            __typename: 'ListItem'
          }
        ],
        id: '736'
      })
    ).toEqual(true)
  })
})
