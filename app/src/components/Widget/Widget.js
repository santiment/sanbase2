import React from 'react'

import './Widget.css'

/*

padding: 5px;
    font-size: 15px;
    margin: 0;
    text-align: center;

    display: block;
    content: '';
    width: 100%;
    height: 1px;
    background: #cacaca;
*/

const Widget = ({ children, title, className = '' }) => {
  return (
    <div className={'Widget ' + className}>
      {title && <h2 className='Widget__title'>{title}</h2>}
      <div className='Widget__content'>{children}</div>
    </div>
  )
}

export default Widget
