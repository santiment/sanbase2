import React from 'react'
import PropTypes from 'prop-types'
import {
  TwitterShareButton,
  TwitterIcon,
  RedditShareButton,
  RedditIcon,
  LinkedinShareButton,
  LinkedinIcon,
  FacebookShareButton,
  FacebookIcon,
  TelegramShareButton,
  TelegramIcon
} from 'react-share'
import './ShareOptions.css'

const ShareOptions = ({ title, url, className = '' }) => (
  <div className={'share-options ' + className}>
    <TwitterShareButton url={url} title={title}>
      <TwitterIcon size={32} round />
    </TwitterShareButton>
    <RedditShareButton url={url} title={title}>
      <RedditIcon size={32} round />
    </RedditShareButton>
    <LinkedinShareButton url={url} title={title}>
      <LinkedinIcon size={32} round />
    </LinkedinShareButton>
    <FacebookShareButton url={url} quote={title}>
      <FacebookIcon size={32} round />
    </FacebookShareButton>
    <TelegramShareButton url={url} title={title}>
      <TelegramIcon size={32} round />
    </TelegramShareButton>
  </div>
)

ShareOptions.propTypes = {
  url: PropTypes.string.isRequired,
  title: PropTypes.string.isRequired,
  className: PropTypes.string
}

export default ShareOptions
