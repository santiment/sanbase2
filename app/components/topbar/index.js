export default (props) => (
  <div className='row topbar'>
    <div className='col-lg-6'>
      <div className='search'>
        <i className='material-icons'>search</i>
      </div>
    </div>
    <div className='col-lg-6'>
      <ul className='nav-right pull-right list-unstyled'>
        <li>
          <span className='balance'>12.5 Ξ</span>
        </li>
        <li />
      </ul>
    </div>
    <style jsx>{`
      .search {
        padding-top: 24px;
        padding-left: 16px;
      }

      .balance {
        display: inline-block;
        padding-top: 22px;
        padding-left: 24px;
        padding-right: 24px;
        font-size: 14px;
      }
    `}</style>
  </div>
)
