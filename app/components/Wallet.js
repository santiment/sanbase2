const Wallet = ({wallet, data}) => {
  var balance = wallet.balance !== null ? wallet.balance : 0;
  return (
  <div className="wallet">
    <div className="usd first">${(balance * eth_price).toLocaleString('en-US', {maximumFractionDigits: 0})}</div>
    <div className="eth">
        <a className="address" href={"https://etherscan.io/address/"+wallet.address} target="_blank">Ξ{balance.toLocaleString('en-US')}
            <i className="fa fa-external-link"></i>
        </a>
    </div>
  </div>
  )
}

export default Wallet
