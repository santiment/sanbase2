
/* Data taken from the original sanbase */

INSERT INTO project (name, ticker, logo_url, coinmarketcap_id) VALUES
  ('EOS','EOS','eos.png','eos'),
  ('Golem','GNT','golem.png','golem-network-tokens'),
  ('Iconomi','ICN','iconomi.png','iconomi'),
  ('Gnosis','GNO','gnosis.png','gnosis-gno'),
  ('Status','SNT','status.png','status'),
  ('TenX','PAY','tenx.png','tenx'),
  ('Basic Attention Token','BAT','basic-attention-token.png','basic-attention-token'),
  ('Populous','PPT','populous.png','populous'),
  ('DigixDAO','DGD','digixdao.png','digixdao'),
  ('Bancor','BNT','bancor.png','bancor'),
  ('MobileGo','MGO','mobilego.png','mobilego'),
  ('Aeternity','AE','aeternity.png','aeternity'),
  ('SingularDTV','SNGLS','singulardtv.png','singulardtv'),
  ('Civic','CVC','civic.png','civic'),
  ('Aragon','ANT','aragon.png','aragon'),
  ('FirstBlood','1ST','firstblood.png','firstblood'),
  ('Etheroll','DICE','etheroll.png','etheroll'),
  ('Melon','MLN','melon.png','melon'),
  ('iExec RLC','RLC','rlc.png','rlc'),
  ('Stox','STX','stox.png','stox'),
  ('Humaniq','HMQ','humaniq.png','humaniq'),
  ('Polybius','PLBT','polybius.png','polybius'),
  ('Santiment','SAN','santiment.png','santiment'),
  ('district0x','DNT','district0x.png','district0x'),
  ('DAO.Casino','BET','dao-casino.png','dao-casino'),
  ('Centra','CTR','centra.png','centra'),
  ('Tierion','TNT','tierion.png','tierion'),
  ('Matchpool','GUP','guppy.png','guppy')

ON CONFLICT (name) DO NOTHING;

INSERT INTO project_eth_address (project_id, address)
  SELECT
    project.id,
    t.address
  FROM
    project,
    (VALUES
      ('EOS','0xA72Dc46CE562f20940267f8deb02746e242540ed'),
      ('Golem','0x7da82c7ab4771ff031b66538d2fb9b0b047f6cf9'),
      ('Iconomi','0x154Af3E01eC56Bc55fD585622E33E3dfb8a248d8'),
      ('Gnosis','0x851b7F3Ab81bd8dF354F0D7640EFcD7288553419'),
      ('Status','0xA646E29877d52B9e2De457ECa09C724fF16D0a2B'),
      ('TenX','0x185f19B43d818E10a31BE68f445ef8EDCB8AFB83'),
      ('Basic Attention Token','0x44fcfaBfBe32024a01b778c025D70498382CCEd0'),
      ('Populous','0xca48BA80Cfa6CC06963B62AeE48000f031c7E2dC'),
      ('DigixDAO','0xf0160428a8552ac9bb7e050d90eeade4ddd52843'),
      ('Bancor','0x5894110995B8c8401Bd38262bA0c8EE41d4E4658'),
      ('MobileGo','0x6d7ea347ef837462a55337C4f772868F2A80B863'),
      ('Aeternity','0x15c19E6c203E2c34D1EDFb26626bfc4F65eF96F0'),
      ('SingularDTV','0x5901Deb2C898D5dBE5923E05e510E95968a35067'),
      ('Civic','0x2323763D78bF7104b54A462A79C2Ce858d118F2F'),
      ('Aragon','0xcafE1A77e84698c83CA8931F54A755176eF75f2C'),
      ('FirstBlood','0xa5384627F6DcD3440298E2D8b0Da9d5F0FCBCeF7'),
      ('Etheroll','0x24C3235558572cff8054b5a419251D3B0D43E91b'),
      ('Melon','0x8615F13C12c24DFdca0ba32511E2861BE02b93b2'),
      ('iExec RLC','0x21346283a31A5AD10Fa64377E77A8900Ac12d469'),
      ('Stox','0x3dD88B391fe62a91436181eD2D43E20B86CDE60c'),
      ('Humaniq','0xa2c9a7578e2172f32a36c5c0e49d64776f9e7883'),
      ('Polybius','0xe9Eca8bB5e61e8e32f26B5E8c117561F68084a9C'),
      ('Santiment','0x6dD5A9F47cfbC44C04a0a4452F0bA792ebfBcC9a'),
      ('district0x','0xd20E4d854C71dE2428E1268167753e4C7070aE68'),
      ('DAO.Casino','0x1446bf7AF9dF857b23a725646D94f9Ec49802227'),
      ('Centra','0x96A65609a7B84E8842732DEB08f56C3E21aC6f8a'),
      ('Tierion','0x0C4b367e876d18d5c102023D9240DD7e9C11b380'),
      ('Matchpool','0x1c10aD0b5f1b4013173f05B4cc05a60cBBAa6536')
    ) AS t (name, address)
  WHERE
    project.name = t.name
ON CONFLICT (address) DO NOTHING;

INSERT INTO tracked_eth (address) VALUES
      ('0xA72Dc46CE562f20940267f8deb02746e242540ed'),
      ('0x7da82c7ab4771ff031b66538d2fb9b0b047f6cf9'),
      ('0x154Af3E01eC56Bc55fD585622E33E3dfb8a248d8'),
      ('0x851b7F3Ab81bd8dF354F0D7640EFcD7288553419'),
      ('0xA646E29877d52B9e2De457ECa09C724fF16D0a2B'),
      ('0x185f19B43d818E10a31BE68f445ef8EDCB8AFB83'),
      ('0x44fcfaBfBe32024a01b778c025D70498382CCEd0'),
      ('0xca48BA80Cfa6CC06963B62AeE48000f031c7E2dC'),
      ('0xf0160428a8552ac9bb7e050d90eeade4ddd52843'),
      ('0x5894110995B8c8401Bd38262bA0c8EE41d4E4658'),
      ('0x6d7ea347ef837462a55337C4f772868F2A80B863'),
      ('0x15c19E6c203E2c34D1EDFb26626bfc4F65eF96F0'),
      ('0x5901Deb2C898D5dBE5923E05e510E95968a35067'),
      ('0x2323763D78bF7104b54A462A79C2Ce858d118F2F'),
      ('0xcafE1A77e84698c83CA8931F54A755176eF75f2C'),
      ('0xa5384627F6DcD3440298E2D8b0Da9d5F0FCBCeF7'),
      ('0x24C3235558572cff8054b5a419251D3B0D43E91b'),
      ('0x8615F13C12c24DFdca0ba32511E2861BE02b93b2'),
      ('0x21346283a31A5AD10Fa64377E77A8900Ac12d469'),
      ('0x3dD88B391fe62a91436181eD2D43E20B86CDE60c'),
      ('0xa2c9a7578e2172f32a36c5c0e49d64776f9e7883'),
      ('0xe9Eca8bB5e61e8e32f26B5E8c117561F68084a9C'),
      ('0x6dD5A9F47cfbC44C04a0a4452F0bA792ebfBcC9a'),
      ('0xd20E4d854C71dE2428E1268167753e4C7070aE68'),
      ('0x1446bf7AF9dF857b23a725646D94f9Ec49802227'),
      ('0x96A65609a7B84E8842732DEB08f56C3E21aC6f8a'),
      ('0x0C4b367e876d18d5c102023D9240DD7e9C11b380'),
      ('0x1c10aD0b5f1b4013173f05B4cc05a60cBBAa6536')
ON CONFLICT (address) DO NOTHING;

/* Data taken from projecttransparency */
/* Populate database with projecttransparency data */
INSERT INTO project (ticker, name, coinmarketcap_id, logo_url) VALUES
  ('ANT', 'Aragon', 'aragon', 'aragon.png'),
  /* ('', 'Attores'), */
  ('CFI', 'Cofound.it', 'cofound-it', 'cofound-it.png'),
  ('DAP', 'Dappbase', null, null),
  ('DNT', 'district0x', 'district0x', 'district0x.png' ),
  ('DNA', 'Encrypgen', null, null),
  ('RSC', 'Etherisc', null, null),
  ('EXP/LAB', 'Expanse/Tokenlab', 'expanse', 'expanse.png'),
  ('GAT', 'Gatcoin.io', null, null),
  ('HSR', 'Hshare', 'hshare', 'hshare.png'),
  ('ICN', 'Iconomi', 'iconomi', 'iconomi.png'),
  ('IND', 'Indorse', 'indorse-token', 'indorse-token.png'),
  /* ('', 'IconiqLab'), */
  /* ('KPMG', 'KPMG'), */
  ('LKK', 'Lykke', 'lykke', 'lykke.png'),
  ('ART', 'Maecenas', 'maecenas', 'maecenas.png'),
  ('MCI', 'Musiconomi', 'musiconomi', 'musiconomi.png'),
  ('SAN', 'Santiment', 'santiment', 'santiment.png'),
  /* ('SNT', 'Status.im', 'status'), */
  ('VIC', 'Virgil Capital', null, null)

ON CONFLICT (name) DO NOTHING;


/* Insert known addresses */
INSERT INTO project_eth_address (project_id, address)
  SELECT
    project.id,
    t.address
  FROM
    project,
    (VALUES
      ('Aragon', '0xcafe1a77e84698c83ca8931f54a755176ef75f2c'),
      ('district0x', '0xd20e4d854c71de2428e1268167753e4c7070ae68'),
      ('Encrypgen', '0x683a0aafa039406c104d814b9f244eea721445a7'),
      ('Etherisc', '0x9B0F6a5a667CB92aF0cd15DbE90E764e32f69e77'),
      ('Etherisc', '0x35792029777427920ce7aDecccE9e645465e9C72'),
      ('Expanse/Tokenlab', '0xd1ea8853619aaad66f3f6c14ca22430ce6954476'),
      ('Expanse/Tokenlab', '0xf83fd4b62ccb4b5c4213278b6b506eb2f19988d0'),
      ('Indorse', '0x1c82ee5b828455F870eb2998f2c9b6Cc2d52a5F6'),
      ('Indorse', '0x26967201d4d1e1aa97554838defa4fc4d010ff6f'),
      ('Iconomi', '0x154Af3E01eC56Bc55fD585622E33E3dfb8a248d8'),
      ('Maecenas', '0x02DC3b8AB87c562CdCE707647bd1ba21C390Faf4'),
      ('Maecenas', '0x9B60874D7bc4e4fBDd142e0F5a12002e4F7715a6'),
      ('Musiconomi', '0xc7CD9d874F93F2409F39A95987b3E3C738313925'),
      ('Santiment', '0x6dd5a9f47cfbc44c04a0a4452f0ba792ebfbcc9a'),
      ('Status', '0xA646E29877d52B9e2De457ECa09C724fF16D0a2B')
    ) AS t (name, address)
  WHERE
    project.name = t.name

ON CONFLICT (address) DO NOTHING;


INSERT INTO project_btc_address (project_id, address)
  SELECT
    project.id,
    t.address
  FROM
    project,
    (VALUES
      ('Encrypgen', '13MoQt2n9cHNzbpt8PfeVYp2cehgzRgj6v'),
      ('Encrypgen', '16bv1XAqh1YadAWHgDWgxKuhhns7T2EywG')
    ) AS t (name, address)
  WHERE
    project.name = t.name

ON CONFLICT (address) DO NOTHING;


/* Set known addresses to tracked */

INSERT INTO tracked_eth (address)
  SELECT
    address
  FROM
    project_eth_address
ON CONFLICT DO NOTHING;

INSERT INTO tracked_btc (address)
  SELECT
    address
  FROM
    project_btc_address
ON CONFLICT DO NOTHING;
