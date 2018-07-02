/* eslint-env jest */
import React from 'react'
import { shallow } from 'enzyme'
import { UnwrappedPost as Post } from './Post'

const user = {
  username: '0xjsadhf92fhk2fjhe',
  email: null
}

const post = {
  id: 0,
  title: '',
  votes: {},
  tags: [],
  createdAt: 0
}

const threeTags = [
  {
    name: 'EOS'
  },
  {
    name: 'BTC'
  },
  {
    name: 'Doge'
  }
]

const postWithTag = {
  ...post,
  tags: [
    threeTags[0]
  ]
}

describe('Post component', () => {
  describe('Tags render', () => {
    it('should render no tags', () => {
      const wrapper = shallow(<Post
        user={user}
        {...post}
      />)
      expect(wrapper.find('.post-tag').length).toBe(0)
    })
    it('should render 1 tag', () => {
      const wrapper = shallow(<Post
        user={user}
        {...postWithTag}
      />)
      expect(wrapper.find('.post-tag').length).toBe(1)
    })
    it('should render 3 tags', () => {
      const wrapper = shallow(<Post
        user={user}
        {...postWithTag}
        tags={threeTags}
      />)
      expect(wrapper.find('.post-tag').length).toBe(3)
    })
    describe('Links', () => {
      it('should render corresponding link', () => {
        const wrapper = shallow(<Post
          user={user}
          {...postWithTag}
        />)
        expect(wrapper.find('.post-tag').prop('to')).toBe('/insights/tags/EOS')
      })
      it('every tag should have correct link("to" prop)', () => {
        const wrapper = shallow(<Post
          user={user}
          {...postWithTag}
          tags={threeTags}
        />)
        const tags = wrapper.find('.post-tag')
        tags.forEach((tag, index) => {
          expect(tag.prop('to')).toBe(`/insights/tags/${threeTags[index].name}`)
        })
      })
    })
  })
})
